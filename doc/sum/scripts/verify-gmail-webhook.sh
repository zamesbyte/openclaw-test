#!/usr/bin/env bash
# 验证 Gmail 官方 Webhook：向 hooks.gmail.account 发一封测试邮件，触发 Pub/Sub → gog serve → OpenClaw /hooks/gmail。
# 不依赖 Agent 工具（gmail_send/gmail_list），仅验证 Webhook 链路。
# 依赖：openclaw 已安装，hooks.gmail.account 已配置，gog 已授权。

set -e
SUBJECT="OpenClaw Webhook 验证"
BODY="这是一封用于验证 Gmail Webhook 的测试邮件。请用一句话回复当前时间。"

# 从 openclaw 配置读取 Gmail 账号
RAW=$(openclaw config get hooks.gmail.account 2>/dev/null || true)
ACCOUNT=$(echo "$RAW" | grep -oE '[a-zA-Z0-9_.+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' | head -1)
if [ -z "$ACCOUNT" ]; then
  echo "错误：未找到 hooks.gmail.account，请先执行："
  echo "  openclaw webhooks gmail setup --account 你的Gmail@gmail.com"
  exit 1
fi

echo "=== Gmail 官方 Webhook 验证 ==="
echo "目标邮箱: $ACCOUNT"
echo "发送测试邮件（主题: $SUBJECT）..."
if ! gog gmail send --account "$ACCOUNT" --to "$ACCOUNT" --subject "$SUBJECT" --body "$BODY" 2>&1; then
  echo "发送失败，请确认 gog 已授权：gog auth list"
  exit 1
fi
echo ""
echo "邮件已发送。请按以下方式检查 Webhook 是否触发："
echo "  1) 查看 Gateway 日志："
echo "     openclaw logs --max-bytes 50000 | grep -iE 'gmail|hook|8788'"
echo "  2) 查看 Gmail Watch 状态："
echo "     gog gmail watch status --account $ACCOUNT"
echo "  3) 若配置了 Agent 回复，请到收件箱查看是否收到 AI 回复邮件。"
echo ""
echo "详细步骤与成功判定见：doc/sum/Gmail官方Webhook集成与验证.md"
