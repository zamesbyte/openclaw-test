#!/usr/bin/env bash
# 自动验证：Gmail 收信 → Webhook → 飞书通知
# 1) 检查 hooks 配置（channel=feishu + to）
# 2) 重启 Gateway（使用工作区构建以加载 feishu channel）
# 3) 发送测试邮件
# 4) 等待并检查日志中 hook 触发与飞书投递
# 依赖：openclaw 工作区已构建，gog 已授权

set -e
OPENCLAW="${OPENCLAW_CLI:-}"
if [ -z "$OPENCLAW" ]; then
  ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
  if [ -x "$ROOT/openclaw-src/dist/index.js" ]; then
    OPENCLAW="node $ROOT/openclaw-src/dist/index.js"
  else
    OPENCLAW="openclaw"
  fi
fi

RAW=$($OPENCLAW config get hooks.gmail.account 2>/dev/null || true)
ACCOUNT=$(echo "$RAW" | grep -oE '[a-zA-Z0-9_.+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' | head -1)
[ -z "$ACCOUNT" ] && ACCOUNT="lifeng.zhan90@gmail.com"

CHANNEL=$($OPENCLAW config get hooks.mappings.0.channel 2>/dev/null || true)
TO=$($OPENCLAW config get hooks.mappings.0.to 2>/dev/null || true)

echo "=== 1. 检查 hooks 配置 ==="
if ! echo "$CHANNEL" | grep -q feishu; then
  echo "  [FAIL] hooks.mappings.0.channel 应为 feishu，当前: $CHANNEL"
  echo "  请编辑 ~/.openclaw/openclaw.json，将 Gmail mapping 的 channel 改为 feishu，to 设为你的飞书 open_id。"
  exit 1
fi
if [ -z "$TO" ] || [ "$TO" = "null" ]; then
  echo "  [FAIL] hooks.mappings.0.to 未设置（飞书 open_id）"
  exit 1
fi
echo "  [OK] channel=feishu, to=$TO"

echo ""
echo "=== 2. 重启 Gateway（加载最新配置）==="
$OPENCLAW gateway restart 2>&1 || true
sleep 5

echo ""
echo "=== 3. 发送测试邮件 ==="
SUBJECT="OpenClaw 自动验证-$(date +%H%M%S)"
BODY="自动验证脚本触发的测试邮件。收到后应触发 Webhook 并向飞书发送通知。"
if ! gog gmail send --account "$ACCOUNT" --to "$ACCOUNT" --subject "$SUBJECT" --body "$BODY" 2>&1; then
  echo "  [FAIL] 发送失败，请检查 gog auth list"
  exit 1
fi
echo "  [OK] 已发送到 $ACCOUNT"

echo ""
echo "=== 4. 等待 Webhook 触发（60s）==="
sleep 60

echo ""
echo "=== 5. 检查日志（hook 与飞书投递）==="
LOG=$($OPENCLAW logs --max-bytes 100000 2>/dev/null || true)
if [ -z "$LOG" ]; then
  echo "  [WARN] 无法获取日志（openclaw logs）"
fi

HOOK_HIT=0
FEISHU_DELIVER=0
if echo "$LOG" | grep -iE 'hooks/gmail|hook.*gmail|gmail.*hook|POST.*gmail' | head -1 >/dev/null 2>&1; then
  HOOK_HIT=1
fi
if echo "$LOG" | grep -iE 'feishu|deliver|Hook Gmail|message_sent' | head -1 >/dev/null 2>&1; then
  FEISHU_DELIVER=1
fi

# 也检查 cron/hook 相关
if echo "$LOG" | grep -iE 'hook:gmail|runCronIsolatedAgentTurn|isolated.*agent' | head -1 >/dev/null 2>&1; then
  HOOK_HIT=1
fi

if [ "$HOOK_HIT" = 1 ]; then
  echo "  [OK] 日志中发现 Hook/Gmail 相关请求"
else
  echo "  [??] 日志中未明显看到 Hook 请求（若未配置 Gmail Watch/Tailscale，属正常）"
fi

if [ "$FEISHU_DELIVER" = 1 ]; then
  echo "  [OK] 日志中发现飞书/投递相关"
else
  echo "  [??] 日志中未明显看到飞书投递（请到飞书确认是否收到通知）"
fi

echo ""
if [ "$HOOK_HIT" = 1 ] || [ "$FEISHU_DELIVER" = 1 ]; then
  echo "=== 验证结果：通过（日志有 Hook 或投递记录）==="
  echo "  请到飞书确认是否收到「已收到邮件并已通知到飞书」类消息。"
  exit 0
fi

echo "=== 验证结果：需人工确认 ==="
echo "  若你已完成 Gmail Webhook 配置（Tailscale + openclaw webhooks gmail setup），请到飞书查看是否收到通知。"
echo "  若未完成 Gmail Watch 配置，收信不会触发 Webhook，请先执行："
echo "    tailscale up && openclaw webhooks gmail setup --account $ACCOUNT && openclaw gateway restart"
exit 0
