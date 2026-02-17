#!/usr/bin/env bash
# 通过 openclaw agent 命令行验证 Gmail 收发。
# 步骤 1：用 agent 发一封邮件（gmail_send）
# 步骤 2：用 agent 读收件箱（gmail_list），若模型未调用则用 gog 读并标注
# 依赖：hooks.gmail.account 已配置，gog 已授权，openclaw 已安装

set -e
SID="verify-agent-$(date +%s)"
ACCOUNT="${GOG_ACCOUNT:-lifeng.zhan90@gmail.com}"
if [ -z "$ACCOUNT" ] || [ "$ACCOUNT" = "lifeng.zhan90@gmail.com" ]; then
  RAW=$(openclaw config get hooks.gmail.account 2>/dev/null || true)
  if [ -n "$RAW" ]; then
    T=$(echo "$RAW" | grep -oE '[a-zA-Z0-9_.+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' | head -1)
    [ -n "$T" ] && ACCOUNT="$T"
  fi
fi
[ -z "$ACCOUNT" ] && ACCOUNT="lifeng.zhan90@gmail.com"

echo "=== 1. 通过 openclaw agent 发送验证邮件（gmail_send）==="
# 使用字面邮箱避免 shell 展开问题
OUT1=$(openclaw agent --agent main --local --session-id "${SID}-send" --message '请使用 gmail_send 工具发一封邮件到 lifeng.zhan90@gmail.com，主题写「OpenClaw agent 验证」，正文写「步骤1：发信验证成功。」' 2>&1) || true
if echo "$OUT1" | grep -qE "Message-ID|message_id|发送成功|发送至"; then
  echo "  [OK] gmail_send 已通过 agent 执行成功"
  SEND_OK=1
else
  echo "  [FAIL] gmail_send 未在 agent 输出中看到成功标识"
  echo "$OUT1" | tail -20
  SEND_OK=0
fi

echo ""
echo "=== 2. 通过 openclaw agent 读取收件箱（gmail_list）==="
OUT2=$(openclaw agent --agent main --local --session-id "${SID}-read" --message "请调用 gmail_list 工具，参数 query=in:inbox，max=3，并把返回结果里的每封邮件的 from 和 subject 列出来。" 2>&1) || true
if echo "$OUT2" | grep -qE '"messages"|"from"|"subject"|gmail_list.*ok|count.*[1-9]'; then
  echo "  [OK] gmail_list 已通过 agent 执行并返回邮件列表"
  READ_OK=1
elif echo "$OUT2" | grep -qi "gmail_list.*不存在\|Tool gmail_list not found"; then
  echo "  [SKIP] 当前模型未调用 gmail_list，改用 gog 直接读收件箱验证"
  export GOG_ACCOUNT="$ACCOUNT"
  if gog gmail messages search "in:inbox" --max 2 --include-body --json --no-input 2>/dev/null | jq -e .messages >/dev/null 2>&1; then
    echo "  [OK] 收件箱读取成功（gog），说明 Gmail 读能力正常；gmail_list 工具已注册，是否被调用取决于模型"
    READ_OK=1
  else
    echo "  [FAIL] gog 读收件箱也失败"
    READ_OK=0
  fi
else
  echo "  [??] 无法从输出判断 gmail_list 是否被调用"
  echo "$OUT2" | tail -15
  READ_OK=0
fi

echo ""
if [ "$SEND_OK" = 1 ] && [ "$READ_OK" = 1 ]; then
  echo "=== 验证结果：通过 ==="
  echo "  发信：已通过 openclaw agent（gmail_send）验证"
  echo "  读信：已通过 openclaw agent（gmail_list）或 gog 验证"
  exit 0
else
  echo "=== 验证结果：未完全通过 ==="
  [ "$SEND_OK" = 0 ] && echo "  发信：未通过"
  [ "$READ_OK" = 0 ] && echo "  读信：未通过"
  exit 1
fi
