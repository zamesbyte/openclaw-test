#!/usr/bin/env bash
# OpenClaw Gmail 能力验证：读最近 2 封邮件 → Agent 总结 → 发一封新邮件到 Gmail
# 使用前：1) 启用 Gmail API  2) 设置 GOG_ACCOUNT=lifeng.zhan90@gmail.com

set -e
ACCOUNT="${GOG_ACCOUNT:?请设置 GOG_ACCOUNT，例如: export GOG_ACCOUNT=lifeng.zhan90@gmail.com}"

echo "=== 1. 读取收件箱最近 2 封邮件 ==="
JSON=$(gog gmail messages search "in:inbox" --max 2 --include-body --json --no-input 2>&1) || true
if ! echo "$JSON" | jq -e . >/dev/null 2>&1; then
  echo "读取邮件失败或未安装 jq。若为 403 accessNotConfigured，请先启用 Gmail API："
  echo "  https://console.developers.google.com/apis/api/gmail.googleapis.com/overview?project=764663573066"
  echo "原始输出: $JSON"
  exit 1
fi

# 构建给 Agent 的摘要：发件人 / 主题 / 摘要（兼容 .messages[] 或 顶层数组）
INPUT=$(echo "$JSON" | jq -r '
  (if type == "array" then . elif .messages then .messages else [.] end) | .[0:2]
  | map(
      "发件人: \(.from // .payload?.headers? // "?")
主题: \(.subject // "?")
摘要: \(.snippet // .body // "?")
---"
    )
  | join("\n")
')
if [ -z "$INPUT" ] || [ "$INPUT" = "null" ]; then
  echo "未解析到邮件内容，请检查 gog 输出格式。"
  exit 1
fi

echo "=== 2. 调用 OpenClaw Agent 总结并生成邮件正文 ==="
PROMPT="下面是我 Gmail 收件箱最近 2 封邮件的摘要，请用 2–3 句话总结要点，并写成一封简短的邮件正文（纯文字，不要称呼和落款），用于发到我的 Gmail 做验证。

$INPUT"
RESPONSE=$(openclaw agent --agent main --local --message "$PROMPT" --json 2>&1) || true
BODY=$(echo "$RESPONSE" | jq -r '.payloads[0].text // .result.payloads[0].text // .result.payloads[0].content // empty' 2>/dev/null)
if [ -z "$BODY" ]; then
  BODY=$(echo "$RESPONSE" | jq -r '.result.payloads[0] // .payloads[0] | if type == "string" then . else .text // .content // empty end' 2>/dev/null)
fi
if [ -z "$BODY" ] || [ "$BODY" = "null" ]; then
  echo "未能从 Agent 输出中解析邮件正文，请手动从下方输出中复制后执行步骤 4："
  echo "$RESPONSE" | jq -r '.result.payloads[]? | .text // .content // .' 2>/dev/null || echo "$RESPONSE"
  exit 1
fi

echo "=== 3. 发送验证邮件到 $ACCOUNT ==="
gog gmail send --to "$ACCOUNT" \
  --subject "OpenClaw 验证：最近 2 封邮件总结" \
  --body "$BODY" \
  --no-input -y

echo "完成。请到 $ACCOUNT 收件箱查看「OpenClaw 验证：最近 2 封邮件总结」。"
