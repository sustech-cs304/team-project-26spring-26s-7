#!/usr/bin/env bash
# =================================================================
# install.sh —— 在华为云生产服务器上一键安装 ItsMapPin 4 个后端服务
#
# 前提：
#   1. 已用 root（或 sudo）跑这个脚本
#   2. 整个 Backend_ItsMapPin/ 已 scp 到 /opt/itsmappin/Backend_ItsMapPin/
#   3. SSL 证书已放到 /etc/nginx/ssl/audit.itsmappin.top/{fullchain,privkey}.pem
#   4. /opt/itsmappin/Backend_ItsMapPin/.env 已填好真实凭证（从 .env.example 复制）
#
# 这脚本会做的事：
#   - 装系统包（nginx, python3-venv）
#   - 建 itsmappin 系统用户、日志目录、数据目录
#   - 建两个 venv 并装依赖
#   - 安装 4 个 systemd unit
#   - 安装 nginx vhost 配置
#   - 起服务、起 nginx
# =================================================================

set -euo pipefail

APP_ROOT=/opt/itsmappin/Backend_ItsMapPin
APP_USER=itsmappin
LOG_DIR=/var/log/itsmappin
DATA_DIR=/var/lib/itsmappin
SSL_DIR=/etc/nginx/ssl/audit.itsmappin.top

# ---- 部署模式 -----------------------------------------------------
# 默认走 "ICP 备案前测试模式"（nginx 监听 :8443，非标端口华为云不拦）
# 备案下来后跑 deploy/scripts/enable-production.sh 切到 :80/:443
# 也可通过环境变量 DEPLOY_MODE=production ./install.sh 直接装生产
DEPLOY_MODE="${DEPLOY_MODE:-test}"
case "$DEPLOY_MODE" in
    test)        NGINX_VHOST=audit.itsmappin.top.test.conf ;;
    production)  NGINX_VHOST=audit.itsmappin.top.prod.conf ;;
    *)           echo "[fatal] DEPLOY_MODE 必须是 test 或 production" >&2; exit 1 ;;
esac
echo "============================================="
echo "  部署模式：DEPLOY_MODE=$DEPLOY_MODE"
echo "  nginx 配置：$NGINX_VHOST"
[[ "$DEPLOY_MODE" == "test" ]] && echo "  对外端口：8443（需安全组放行）"
[[ "$DEPLOY_MODE" == "production" ]] && echo "  对外端口：80 + 443（要求 ICP 备案已通过）"
echo "============================================="

if [[ $EUID -ne 0 ]]; then
    echo "请用 sudo 跑这个脚本" >&2
    exit 1
fi

if [[ ! -d $APP_ROOT ]]; then
    echo "[fatal] 找不到 $APP_ROOT，请先 scp 整个 Backend_ItsMapPin/ 到这个路径" >&2
    exit 1
fi

if [[ ! -f $APP_ROOT/.env ]]; then
    echo "[fatal] 没有 $APP_ROOT/.env，请先 cp .env.example .env 并填好凭证" >&2
    exit 1
fi


# ---------- 1. 系统包 ----------
echo "[1/8] 装系统包"
. /etc/os-release || true
case "${ID:-}" in
  ubuntu|debian)
    apt-get update -qq
    apt-get install -y nginx python3 python3-venv python3-pip curl nodejs npm
    ;;
  centos|rhel|euleros|opencloudos|kylin|openeuler)
    yum install -y nginx python3 python3-pip curl nodejs npm
    ;;
  *)
    echo "[warn] 未识别的发行版 ${ID:-unknown}，请手动确保 nginx + python3 已装"
    ;;
esac


# ---------- 2. 用户 / 目录 ----------
echo "[2/8] 建用户和目录"
id -u $APP_USER &>/dev/null || useradd --system --no-create-home --shell /usr/sbin/nologin $APP_USER
mkdir -p "$LOG_DIR" "$DATA_DIR"
chown -R $APP_USER:$APP_USER "$LOG_DIR" "$DATA_DIR" "$APP_ROOT"
chmod 750 "$LOG_DIR" "$DATA_DIR"
chmod 640 "$APP_ROOT/.env"
chown $APP_USER:$APP_USER "$APP_ROOT/.env"


# ---------- 3. 主 venv（ai/sensitive/picture 共用） ----------
echo "[3/8] 建主 venv 并装依赖"
sudo -u $APP_USER bash <<EOF
set -e
cd "$APP_ROOT"
python3 -m venv .venv
. .venv/bin/activate
pip install --upgrade pip
pip install -r ai-relay/requirements.txt
EOF

if [[ -f "$APP_ROOT/sensitive-check/package.json" ]]; then
    echo "[3b/8] 安装 sensitive-check Node.js 依赖"
    sudo -u $APP_USER bash <<EOF
set -e
cd "$APP_ROOT/sensitive-check"
npm install --omit=dev
EOF
fi


# ---------- 4. share-service 单独 venv ----------
echo "[4/8] 建 share-service venv"
sudo -u $APP_USER bash <<EOF
set -e
cd "$APP_ROOT/share-service"
python3 -m venv .venv
. .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
EOF


# ---------- 5. systemd unit ----------
echo "[5/8] 安装 systemd unit"
install -m 0644 "$APP_ROOT/deploy/systemd/ai-relay.service"        /etc/systemd/system/
install -m 0644 "$APP_ROOT/deploy/systemd/sensitive-filter.service" /etc/systemd/system/
install -m 0644 "$APP_ROOT/deploy/systemd/picture-check.service"   /etc/systemd/system/
install -m 0644 "$APP_ROOT/deploy/systemd/share-service.service"   /etc/systemd/system/
systemctl daemon-reload


# ---------- 6. SSL 证书校验 ----------
echo "[6/8] 校验 SSL 证书"
if [[ ! -f $SSL_DIR/scs1778605232652_audit.itsmappin.top_server.crt || ! -f $SSL_DIR/scs1778605232652_audit.itsmappin.top_server.key ]]; then
    echo "[fatal] 找不到 SSL 证书：" >&2
    echo "  $SSL_DIR/scs1778605232652_audit.itsmappin.top_server.crt" >&2
    echo "  $SSL_DIR/scs1778605232652_audit.itsmappin.top_server.key" >&2
    echo "请先到华为云控制台 → SSL 证书管理 → 申请免费证书 → 下载 nginx 版" >&2
    echo "解压后把里面的 .crt 和 .key 文件放到上面的路径" >&2
    exit 1
fi
chmod 600 "$SSL_DIR/scs1778605232652_audit.itsmappin.top_server.key"


# ---------- 7. nginx 配置 ----------
echo "[7/8] 装 nginx vhost"

# 设置私钥权限
chmod 600 /etc/nginx/ssl/audit.itsmappin.top/scs1778605232652_audit.itsmappin.top_server.key

install -m 0644 "$APP_ROOT/deploy/nginx/$NGINX_VHOST" /etc/nginx/conf.d/$NGINX_VHOST

# 修复 nginx 1.18 的 http2 语法兼容性问题
echo "  修复 http2 语法以兼容 nginx $(nginx -v 2>&1 | cut -d'/' -f2)"
sed -i 's/listen 443 ssl;/listen 443 ssl http2;/g' /etc/nginx/conf.d/$NGINX_VHOST
sed -i 's/listen \[::\]:443 ssl;/listen [::]:443 ssl http2;/g' /etc/nginx/conf.d/$NGINX_VHOST
sed -i '/http2 on;/d' /etc/nginx/conf.d/$NGINX_VHOST

# 修改证书路径为实际的文件名
sed -i 's|fullchain.pem|scs1778605232652_audit.itsmappin.top_server.crt|g' /etc/nginx/conf.d/$NGINX_VHOST
sed -i 's|privkey.pem|scs1778605232652_audit.itsmappin.top_server.key|g' /etc/nginx/conf.d/$NGINX_VHOST

# 确保 acme webroot 存在
mkdir -p /var/www/acme

# 测试 nginx 配置
nginx -t


# ---------- 8. 启动一切 ----------
echo "[8/8] 启动服务"
# 启动顺序：filter 最先（被 ai-relay 依赖）
for svc in picture-check ai-relay share-service; do
    systemctl enable "$svc"
    systemctl restart "$svc"
    sleep 1
done

# 启 nginx
systemctl enable nginx
systemctl restart nginx


# ---------- 验证 ----------
if [[ "$DEPLOY_MODE" == "test" ]]; then
    PUBLIC_BASE="https://audit.itsmappin.top:8443"
    PORT_LIST_REGEX='[:.](8000|8001|9100|9200|8443)$'
else
    PUBLIC_BASE="https://audit.itsmappin.top"
    PORT_LIST_REGEX='[:.](8000|8001|9100|9200|443|80)$'
fi

echo ""
echo "=========================================="
echo "安装完成。状态："
ss -tln 2>/dev/null | awk -v re="$PORT_LIST_REGEX" '$4 ~ re {print "  ✓ "$4}'
echo ""
echo "本机自测："
for path in /health /health/ai /health/share /health/filter /health/censor; do
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -k "$PUBLIC_BASE$path" 2>&1)
    echo "  $path → HTTP $code"
done
echo ""
echo "公网测试 URL：$PUBLIC_BASE/health"
if [[ "$DEPLOY_MODE" == "test" ]]; then
    echo ""
    echo "⚠️ 下一步："
    echo "  1. 华为云控制台 → 安全组 → 入方向放行 TCP 8443（0.0.0.0/0）"
    echo "  2. 备案审批通过后，跑 sudo $APP_ROOT/deploy/scripts/enable-production.sh"
fi
echo ""
echo "看日志：journalctl -u <service> -f"
echo "停服务：systemctl stop ai-relay share-service sensitive-filter picture-check"
echo "=========================================="
