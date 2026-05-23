#!/usr/bin/env bash
# =================================================================
# Backend_ItsMapPin —— 一键启动所有 4 个后端服务
#
# 用法：
#   1. 先按 README.md 第二步配好 Python venv 和依赖
#   2. cp .env.example .env  并填好凭证
#   3. ./start_all.sh
#
# 默认所有进程都用 nohup 后台跑，PID 写到 logs/<svc>.pid
# 公网暴露走 cloudflared，需要时单独起（见 README.md 第五节）
# =================================================================

set -e
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"

# ---------- 1. 加载 .env ----------
if [[ ! -f .env ]]; then
  echo "[fatal] 找不到 .env。请先：cp .env.example .env 并填好凭证"
  exit 1
fi
set -a
# shellcheck disable=SC1091
source .env
set +a

# 启动 cloudflared / 后端时不让 HTTP_PROXY 干扰
# （ai-relay 内部已分两个 httpx client 自行处理，但 cloudflared 不行）
unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy

LOG_DIR="${LOG_DIR:-$HERE/logs}"
mkdir -p "$LOG_DIR"

# 端口冲突检测
check_port() {
  local p=$1 svc=$2
  if ss -tln 2>/dev/null | awk '{print $4}' | grep -qE "[:.]$p$"; then
    echo "[skip] :$p 已被占用，跳过启动 $svc"
    return 1
  fi
}

# 通用 nohup 启动 + pidfile
launch() {
  local svc=$1; shift
  local cwd=$1; shift
  echo "[start] $svc ..."
  ( cd "$cwd" && nohup "$@" \
      >>"$LOG_DIR/${svc}.log" 2>>"$LOG_DIR/${svc}.err" </dev/null & echo $! >"$LOG_DIR/${svc}.pid" )
  sleep 1
  local pid; pid=$(cat "$LOG_DIR/${svc}.pid")
  if kill -0 "$pid" 2>/dev/null; then
    echo "  → $svc PID=$pid  (log: $LOG_DIR/${svc}.log)"
  else
    echo "  → [fail] $svc 没起来，看 $LOG_DIR/${svc}.err"
  fi
}


# ---------- 2. sensitive-filter (:9100) ----------
# 先启动它，ai-relay 启动时会试探 /health
if check_port 9100 sensitive-filter; then
  export SF_WORDS_FILE="$HERE/sensitive-filter/data/sensitive_words.txt"
  export SF_WHITELIST_FILE="$HERE/sensitive-filter/data/whitelist.txt"
  launch sensitive-filter "$HERE/sensitive-filter" \
    "$HERE/.venv/bin/python" sensitive_filter_service.py
fi


# ---------- 3. picture-check (:9200) ----------
if check_port 9200 picture-check; then
  if [[ -z "$BIC_API_KEY" || "$BIC_API_KEY" == "replace-me" ]]; then
    echo "[skip] BIC_API_KEY 未配置，跳过 picture-check"
  else
    launch picture-check "$HERE/picture-check" \
      "$HERE/.venv/bin/python" baidu_image_censor.py
  fi
fi


# ---------- 4. ai-relay (:8000) ----------
if check_port 8000 ai-relay; then
  if [[ -z "$SF_KEY" || "$SF_KEY" == sk-replace-me* ]]; then
    echo "[skip] SF_KEY 未配置，跳过 ai-relay"
  else
    launch ai-relay "$HERE/ai-relay" \
      "$HERE/.venv/bin/python" siliconflow_relay.py \
        --server-host 127.0.0.1 \
        --server-port 8000 \
        --api-keys "$AI_SERVICE_API_KEYS" \
        --rate-limit-per-min "${AI_SERVICE_RATE_LIMIT_PER_MIN:-30}" \
        --max-question-chars "${AI_SERVICE_MAX_QUESTION_CHARS:-3000}" \
        --siliconflow-key "$SF_KEY" \
        --sensitive-filter-url "http://127.0.0.1:${SF_PORT:-9100}"
  fi
fi


# ---------- 5. share-service (:8001) ----------
if check_port 8001 share-service; then
  if [[ -z "$SHARE_HMAC_KEY" || "$SHARE_HMAC_KEY" == replace-me* ]]; then
    echo "[skip] SHARE_HMAC_KEY 未配置，跳过 share-service"
  else
    launch share-service "$HERE/share-service" \
      "$HERE/share-service/.venv/bin/uvicorn" \
        share_service.main:app --host 127.0.0.1 --port 8001
  fi
fi


echo ""
echo "=========================================="
echo "全部启动完成。状态："
ss -tln 2>/dev/null | awk '$4 ~ /[:.](8000|8001|9100|9200)$/ {print "  ✓ "$4}'
echo "日志目录：$LOG_DIR"
echo "停止：./stop_all.sh"
echo "=========================================="
