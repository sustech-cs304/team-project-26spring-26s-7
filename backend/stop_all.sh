#!/usr/bin/env bash
# 停止 start_all.sh 起的所有后端进程。优雅 → 强制。
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
LOG_DIR="${LOG_DIR:-$HERE/logs}"

stop_svc() {
  local svc=$1
  local pidfile="$LOG_DIR/${svc}.pid"
  if [[ ! -f $pidfile ]]; then
    echo "[skip] $svc: no pidfile"
    return
  fi
  local pid; pid=$(cat "$pidfile")
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "[skip] $svc: PID $pid 已不在"
    rm -f "$pidfile"
    return
  fi
  echo "[stop] $svc PID=$pid"
  kill "$pid" 2>/dev/null || true
  for _ in 1 2 3 4 5 6 7 8; do
    sleep 0.5
    kill -0 "$pid" 2>/dev/null || { rm -f "$pidfile"; return; }
  done
  echo "  → 还活着，KILL"
  kill -9 "$pid" 2>/dev/null || true
  rm -f "$pidfile"
}

for s in ai-relay share-service sensitive-filter picture-check; do
  stop_svc "$s"
done

echo "--- 剩余监听端口 ---"
ss -tln 2>/dev/null | awk '$4 ~ /[:.](8000|8001|9100|9200)$/ {print "  ⚠ 仍在监听: "$4}' || true
