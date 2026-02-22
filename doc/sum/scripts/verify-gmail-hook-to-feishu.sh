#!/usr/bin/env bash
# 验证 Gmail Hook → 飞书 链路（模拟一次 POST /hooks/gmail，确认飞书能收到）。
# 不依赖真实 Gmail 收信，用于确认 OpenClaw 侧配置与投递正常。
# 用法：bash doc/sum/scripts/verify-gmail-hook-to-feishu.sh

set -e
OPENCLAW="${OPENCLAW_CLI:-openclaw}"
TOKEN=$($OPENCLAW config get hooks.token 2>/dev/null | grep -oE '[a-f0-9]{40,}' | head -1)
if [ -z "$TOKEN" ]; then
  echo "[FAIL] 无法读取 hooks.token，请检查 ~/.openclaw/openclaw.json"
  exit 1
fi

URL="http://127.0.0.1:18789/hooks/gmail"
ID="verify-$(date +%s)"
BODY=$(cat <<EOF
{"messages":[{"id":"$ID","from":"verify@openclaw.local","subject":"[验证] Gmail→飞书 链路测试","snippet":"若飞书收到本条，说明 Hook 投递正常。","body":"本邮件为 OpenClaw 验证脚本模拟，用于测试 Gmail Hook 到飞书的投递。"}]}
EOF
)

echo "=== 1. 发送模拟 Gmail Hook 到 $URL ==="
RESP=$(curl -s -w "\n%{http_code}" -X POST "$URL" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "$BODY" 2>&1) || true
HTTP_CODE=$(echo "$RESP" | tail -1)
BODY_RESP=$(echo "$RESP" | sed '$d')

if [ "$HTTP_CODE" != "202" ]; then
  echo "  [FAIL] 期望 HTTP 202，得到 $HTTP_CODE"
  echo "$BODY_RESP"
  exit 1
fi
if ! echo "$BODY_RESP" | grep -q '"ok":true'; then
  echo "  [FAIL] 响应未包含 ok:true"
  echo "$BODY_RESP"
  exit 1
fi
echo "  [OK] Hook 已接受 (202)"

echo ""
echo "=== 2. 等待 Agent 执行并投递到飞书（约 20s）==="
sleep 20

echo ""
echo "=== 3. 检查日志中是否出现飞书投递 ==="
LOG=$($OPENCLAW logs --max-bytes 50000 2>/dev/null | grep -E "\[feishu\] sent text|feishu.*deliver|messageId=om_" | tail -3)
if echo "$LOG" | grep -q "feishu.*sent\|messageId=om_"; then
  echo "  [OK] 日志中可见飞书发送记录，请到飞书确认是否收到一条「Gmail→飞书 链路测试」相关消息。"
  exit 0
fi
echo "  [??] 未在近期日志中看到飞书 sent；请到飞书查看是否收到消息，或执行: openclaw logs --follow"
exit 0
