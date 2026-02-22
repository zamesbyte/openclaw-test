#!/usr/bin/env bash
# 本地服务内网穿透，供 Gmail Pub/Sub Push 调用
# 用法：
#   bash doc/sum/scripts/gmail-push-expose.sh              # 优先 Tailscale，否则 cloudflared
#   bash doc/sum/scripts/gmail-push-expose.sh tailscale    # 仅 Tailscale
#   bash doc/sum/scripts/gmail-push-expose.sh cloudflared   # 仅 cloudflared
#
# 依赖：openclaw 已配置 hooks.gmail.account，且 gcloud/gog 已就绪

set -e
MODE="${1:-}"
OPENCLAW="${OPENCLAW_CLI:-openclaw}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
[ -x "$ROOT/openclaw-src/dist/index.js" ] && OPENCLAW="node $ROOT/openclaw-src/dist/index.js"

ACCOUNT=$($OPENCLAW config get hooks.gmail.account 2>/dev/null | tr -d '"' | grep -oE '[a-zA-Z0-9_.+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' | head -1)
[ -z "$ACCOUNT" ] && ACCOUNT="你的Gmail@gmail.com"

echo "=== Gmail Push 内网穿透与 Setup ==="
echo "  account: ${ACCOUNT}"
echo ""

# ---------- Tailscale ----------
do_tailscale() {
  if ! command -v tailscale >/dev/null 2>&1; then
    echo "[SKIP] Tailscale 未安装。安装: brew install tailscale"
    return 1
  fi
  if ! tailscale status --json 2>/dev/null | grep -q '"Self"'; then
    echo "[FAIL] Tailscale 未登录。请先运行: tailscale up"
    return 1
  fi
  echo "[OK] Tailscale 已就绪，执行 webhooks gmail setup（Funnel）..."
  $OPENCLAW webhooks gmail setup --account "$ACCOUNT"
  echo ""
  echo "接下来请执行: $OPENCLAW gateway restart"
  return 0
}

# ---------- Cloudflared ----------
do_cloudflared() {
  if ! command -v cloudflared >/dev/null 2>&1; then
    echo "[FAIL] cloudflared 未安装。安装: brew install cloudflared"
    return 1
  fi
  echo "1) 启动 cloudflared 隧道（后台），等待公网 URL..."
  ( cloudflared tunnel --url http://127.0.0.1:8788 --no-autoupdate 2>&1 | tee /tmp/openclaw-cloudflared.log & )
  sleep 10
  URL=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' /tmp/openclaw-cloudflared.log 2>/dev/null | head -1)
  if [ -z "$URL" ]; then
    echo "[WARN] 未从日志中解析到 URL，请查看 /tmp/openclaw-cloudflared.log 中的 trycloudflare.com 地址"
    echo "       然后手动执行 setup（见下方命令）。"
    return 1
  fi
  echo "  [OK] 公网 URL: $URL"
  echo ""
  PUSH_TOKEN=$($OPENCLAW config get hooks.gmail.pushToken 2>/dev/null | tr -d '"')
  if [ -z "$PUSH_TOKEN" ] || [ "$PUSH_TOKEN" = "null" ]; then
    PUSH_TOKEN=$(python3 -c "import secrets; print(secrets.token_hex(24))" 2>/dev/null || openssl rand -hex 24)
  fi
  PUSH_ENDPOINT="${URL}/gmail-pubsub?token=${PUSH_TOKEN}"
  echo "2) 执行 webhooks gmail setup（push-endpoint = cloudflared）..."
  $OPENCLAW webhooks gmail setup --account "$ACCOUNT" --tailscale off --push-token "$PUSH_TOKEN" --push-endpoint "$PUSH_ENDPOINT"
  echo ""
  echo "3) 请执行: $OPENCLAW gateway restart"
  echo "注意: cloudflared 为临时隧道，重启后 URL 会变，需重新运行本脚本（cloudflared）并再次 setup。"
  return 0
}

# ---------- 主分支 ----------
case "$MODE" in
  tailscale)
    do_tailscale
    ;;
  cloudflared)
    do_cloudflared
    ;;
  *)
    if tailscale status --json 2>/dev/null | grep -q '"Self"'; then
      do_tailscale
    else
      echo "Tailscale 未运行，改用 cloudflared..."
      do_cloudflared
    fi
    ;;
esac
