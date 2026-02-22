#!/usr/bin/env bash
# 向指定邮箱发送一封测试邮件（使用 hooks.gmail.account + gog）。
# 用法：./send-test-email.sh [收件人]
# 默认收件人：lifengzhan16@gmail.com

set -e
TO="${1:-lifengzhan16@gmail.com}"
OPENCLAW="${OPENCLAW_CLI:-openclaw}"
RAW=$($OPENCLAW config get hooks.gmail.account 2>/dev/null || true)
ACCOUNT=$(echo "$RAW" | grep -oE '[a-zA-Z0-9_.+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' | head -1)
[ -z "$ACCOUNT" ] && ACCOUNT="lifeng.zhan90@gmail.com"

if ! command -v gog >/dev/null 2>&1; then
  echo "[FAIL] gog 未安装或不在 PATH。安装: brew install steipete/tap/gogcli"
  exit 1
fi

echo "发件账号（hooks.gmail.account）: $ACCOUNT"
echo "收件人: $TO"
SUBJECT="OpenClaw 测试邮件 $(date +%H:%M:%S)"
BODY="这是一封由 OpenClaw 验证脚本通过 gog 发送的测试邮件。若你收到且 Gmail Webhook 已配置，飞书应收到通知。"

export GOG_ACCOUNT="$ACCOUNT"
if gog gmail send --to "$TO" --subject "$SUBJECT" --body "$BODY" --no-input -y 2>&1; then
  echo "[OK] 已发送到 $TO"
  exit 0
else
  echo "[FAIL] 发送失败。请执行: gog auth add $ACCOUNT --services gmail"
  exit 1
fi
