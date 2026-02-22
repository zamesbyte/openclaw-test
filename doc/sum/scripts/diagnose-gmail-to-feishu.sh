#!/usr/bin/env bash
# Gmail 收件 → 飞书推送 深度诊断：逐环检查配置、进程与推送可达性。
# 用法：bash doc/sum/scripts/diagnose-gmail-to-feishu.sh

set -e
OPENCLAW="${OPENCLAW_CLI:-openclaw}"
if command -v node >/dev/null 2>&1; then
  ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
  [ -x "$ROOT/openclaw-src/dist/index.js" ] && OPENCLAW="node $ROOT/openclaw-src/dist/index.js"
fi

echo "========== 1. hooks.gmail 配置 =========="
ACCOUNT=$($OPENCLAW config get hooks.gmail.account 2>/dev/null | tr -d '"' || true)
TOPIC=$($OPENCLAW config get hooks.gmail.topic 2>/dev/null | tr -d '"' || true)
PUSH_TOKEN=$($OPENCLAW config get hooks.gmail.pushToken 2>/dev/null | tr -d '"' || true)
TS_MODE=$($OPENCLAW config get hooks.gmail.tailscale.mode 2>/dev/null | tr -d '"' || true)
HOOK_URL=$($OPENCLAW config get hooks.gmail.hookUrl 2>/dev/null | tr -d '"' || true)

if [ -z "$ACCOUNT" ] || [ "$ACCOUNT" = "null" ]; then
  echo "  [FAIL] hooks.gmail.account 未配置"
  echo "  修复: 在 ~/.openclaw/openclaw.json 中设置 hooks.gmail.account 或执行:"
  echo "    $OPENCLAW webhooks gmail setup --account 你的Gmail@gmail.com"
  exit 1
fi
echo "  [OK] account=$ACCOUNT"

if [ -z "$TOPIC" ] || [ "$TOPIC" = "null" ]; then
  echo "  [FAIL] hooks.gmail.topic 未配置 → Google Push 未注册"
  echo "  修复: 执行 $OPENCLAW webhooks gmail setup --account $ACCOUNT"
  echo "        会创建 Pub/Sub topic 并注册 push endpoint（需 Tailscale 或 --push-endpoint）"
  exit 1
fi
echo "  [OK] topic=$TOPIC"

if [ -z "$PUSH_TOKEN" ] || [ "$PUSH_TOKEN" = "null" ]; then
  echo "  [WARN] hooks.gmail.pushToken 未配置（setup 会自动生成）"
fi

echo "  tailscale.mode=${TS_MODE:-未设置}"
echo "  hookUrl=${HOOK_URL:-未设置}"
echo ""

echo "========== 2. 公网 Push 可达性（Google 能否推到你本机） =========="
if [ "$TS_MODE" = "off" ] || [ -z "$TS_MODE" ]; then
  echo "  [WARN] Tailscale 未启用。Google Pub/Sub 只能往公网 URL 推送。"
  echo "  若未配置 --push-endpoint（如 cloudflared URL），真实收信不会触发 Hook。"
  echo "  修复: 二选一"
  echo "    A) tailscale up && $OPENCLAW webhooks gmail setup --account $ACCOUNT"
  echo "    B) 用 cloudflared 暴露 8788 后: $OPENCLAW webhooks gmail setup --account $ACCOUNT --tailscale off --push-endpoint 'https://你的隧道URL/gmail-pubsub?token=...'"
else
  if ! command -v tailscale >/dev/null 2>&1; then
    echo "  [WARN] tailscale 未安装或不在 PATH"
  else
    TS_STATUS=$(tailscale status --json 2>/dev/null | head -1)
    if [ -z "$TS_STATUS" ]; then
      echo "  [WARN] tailscale status 无法读取（未登录或未运行?）"
    else
      echo "  [OK] Tailscale 已配置；Push 应指向你的 Tailscale Funnel URL"
    fi
  fi
fi
echo ""

echo "========== 3. Gateway 与 gog serve（本机接收 Push 的进程） =========="
GW_REACHABLE=0
if curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:18789/health" 2>/dev/null | grep -q 200; then
  GW_REACHABLE=1
  echo "  [OK] Gateway 18789 可达"
else
  echo "  [FAIL] Gateway 不可达 (127.0.0.1:18789)"
  echo "  修复: openclaw gateway start 或 gateway restart"
fi

GOG_LISTEN=0
if command -v lsof >/dev/null 2>&1; then
  if lsof -i :8788 -sTCP:LISTEN 2>/dev/null | grep -q .; then
    GOG_LISTEN=1
    echo "  [OK] 端口 8788 有进程监听（gog gmail watch serve）"
  fi
fi
if [ "$GOG_LISTEN" = 0 ]; then
  echo "  [??] 端口 8788 未监听。Gateway 启动时应自动拉起的 gog serve 可能未启动。"
  echo "  查看: $OPENCLAW logs --max-bytes 30000 | grep -E 'gmail watcher|gog.*gmail'"
fi
echo ""

echo "========== 4. OpenClaw 侧：模拟 Hook → 飞书 =========="
echo "  执行模拟 POST /hooks/gmail，确认网关到飞书是否正常..."
bash "$(dirname "$0")/verify-gmail-hook-to-feishu.sh" 2>&1 || true
echo ""

echo "========== 5. 近期日志（Hook 与飞书） =========="
LOG=$($OPENCLAW logs --max-bytes 50000 2>/dev/null || true)
if echo "$LOG" | grep -q "gmail watcher started"; then
  echo "  [OK] 日志中有 gmail watcher started"
else
  echo "  [??] 未看到 gmail watcher started（可能未配置 topic 或 gog 不可用）"
fi
if echo "$LOG" | grep -qE "hooks/gmail|hook:gmail|POST.*gmail"; then
  echo "  [OK] 日志中有 /hooks/gmail 或 hook:gmail 请求"
else
  echo "  [??] 未看到 Hook 请求（真实收信未触发或 Push 未到本机）"
fi
if echo "$LOG" | grep -qE "\[feishu\].*sent|feishu.*deliver"; then
  echo "  [OK] 日志中有飞书发送记录"
else
  echo "  [??] 未看到飞书 sent（检查 hooks.mappings channel=feishu, to=open_id）"
fi
echo ""
echo "========== 诊断结束 =========="
echo "若模拟 Hook 能收到飞书、真实收信不能：问题在「Google Push 未到本机」，按上面 2 修复。"
echo "若模拟也收不到：检查 hooks.mappings 与 openclaw channels resolve 的 open_id。"
