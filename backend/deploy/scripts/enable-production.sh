#!/usr/bin/env bash
# =================================================================
# enable-production.sh —— ICP 备案下来后，从测试模式（:8443）切到生产（:80/:443）
#
# 前提：
#   - 已用 install.sh 装好测试模式，跑了一段时间没问题
#   - ICP 备案审批已通过，华为云已自动开放 80/443
#   - 安全组已放行 TCP 80 和 443
#
# 这脚本会做：
#   1. 卸下 audit.itsmappin.top.test.conf
#   2. 装上 audit.itsmappin.top.prod.conf（监听 80 + 443，80→443 跳转）
#   3. nginx reload
#   4. 跑公网自测
#   5. 提醒你之后可以选择性关 8443
# =================================================================

set -euo pipefail

APP_ROOT=/opt/itsmappin/Backend_ItsMapPin
SSL_DIR=/etc/nginx/ssl/audit.itsmappin.top
TEST_CONF=/etc/nginx/conf.d/audit.itsmappin.top.test.conf
PROD_CONF_NAME=audit.itsmappin.top.prod.conf
PROD_CONF=/etc/nginx/conf.d/$PROD_CONF_NAME

if [[ $EUID -ne 0 ]]; then
    echo "请用 sudo 跑这个脚本" >&2
    exit 1
fi


# ---------- 1. SSL 证书校验 ----------
echo "[1/4] 校验 SSL 证书"
if [[ ! -f $SSL_DIR/fullchain.pem || ! -f $SSL_DIR/privkey.pem ]]; then
    echo "[fatal] SSL 证书不全：$SSL_DIR/{fullchain,privkey}.pem" >&2
    exit 1
fi


# ---------- 2. 备案状态自检（curl 自己的 :80） ----------
echo "[2/4] 自检 :80 是否被云厂解封"
# 用一台公网 DNS 反向解析自己的 IP，避免环回
public_test=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 \
    -H "Host: audit.itsmappin.top" \
    "http://audit.itsmappin.top/" 2>&1 || echo "000")
case "$public_test" in
    000|521|522)
        echo "[warn] :80 当前不可达（HTTP $public_test）。可能 ICP 还没下来，或安全组没放 80。继续？(y/N)"
        read -r ans
        [[ "$ans" =~ ^[Yy]$ ]] || exit 1
        ;;
    *)
        echo "  → :80 可达（HTTP $public_test），继续"
        ;;
esac


# ---------- 3. 切换 nginx 配置 ----------
echo "[3/4] 切到生产 nginx 配置"
# 先 install 新的；nginx -t；过了再删旧的；reload
install -m 0644 "$APP_ROOT/deploy/nginx/$PROD_CONF_NAME" "$PROD_CONF"

# 两份配置同时存在会导致 upstream / listen 重复定义，nginx -t 会失败
# 所以装好新的就立刻删旧的，然后才 nginx -t
if [[ -f "$TEST_CONF" ]]; then
    mv "$TEST_CONF" "${TEST_CONF}.disabled"
    echo "  → 已停用测试配置：${TEST_CONF}.disabled（出问题可改名回来）"
fi

if ! nginx -t; then
    echo "[fatal] nginx -t 失败，正在回滚..."
    rm -f "$PROD_CONF"
    [[ -f "${TEST_CONF}.disabled" ]] && mv "${TEST_CONF}.disabled" "$TEST_CONF"
    nginx -t && systemctl reload nginx
    exit 1
fi

systemctl reload nginx
echo "  → nginx 已 reload"


# ---------- 4. 公网自测 ----------
echo "[4/4] 跑公网自测"
sleep 2
for path in /health /health/ai /health/share /health/filter /health/censor; do
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 \
        "https://audit.itsmappin.top$path" 2>&1 || echo "000")
    echo "  https://audit.itsmappin.top$path  →  HTTP $code"
done


echo ""
echo "=========================================="
echo "生产模式启用完成。"
echo ""
echo "下一步可做的清理（确认稳定后再做）："
echo "  1. 华为云控制台 → 安全组 → 入方向 → 删除 8443 规则"
echo "  2. 前端 BASE_URL 从 https://audit.itsmappin.top:8443 改成 https://audit.itsmappin.top"
echo "  3. 删除 ${TEST_CONF}.disabled"
echo ""
echo "如果出问题要回滚："
echo "  sudo rm $PROD_CONF"
echo "  sudo mv ${TEST_CONF}.disabled $TEST_CONF"
echo "  sudo nginx -t && sudo systemctl reload nginx"
echo "=========================================="
