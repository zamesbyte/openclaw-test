#!/usr/bin/env bash
# 验证 OpenClaw 已注册 gemini_cli 与 cursor_cli 工具（不要求本机已安装 gemini/cursor）
# 用法：从仓库根目录执行
#   doc/sum/scripts/verify-ai-code-cli-tools.sh
# 或指定 openclaw 源码目录：
#   OPENCLAW_SRC=./openclaw-src doc/sum/scripts/verify-ai-code-cli-tools.sh

set -e
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
OPENCLAW_SRC="${OPENCLAW_SRC:-$REPO_ROOT/openclaw-src}"
cd "$REPO_ROOT"

echo "=== 1. 检查 openclaw-src 与构建 ==="
if [ ! -d "$OPENCLAW_SRC" ]; then
  echo "错误: 未找到 $OPENCLAW_SRC"
  exit 1
fi
if [ ! -f "$OPENCLAW_SRC/dist/agents/openclaw-tools.js" ]; then
  echo "构建 openclaw-src..."
  (cd "$OPENCLAW_SRC" && npm run build)
fi

echo "=== 2. 检查工具注册（gemini_cli / cursor_cli）==="
(cd "$OPENCLAW_SRC" && pnpm test -- src/agents/openclaw-tools.ai-code-cli.test.ts --run)

echo "=== 3. 可选：若已安装 gemini，用 openclaw agent 调 gemini_cli ==="
if command -v gemini >/dev/null 2>&1; then
  echo "检测到 gemini，运行一次 agent 调用 gemini_cli..."
  OPENCLAW_CMD="${OPENCLAW_CMD:-openclaw}"
  RESP=$("$OPENCLAW_CMD" agent --agent main --local --message "请用工具 gemini_cli 问一句：1+1 等于几？只返回数字。" --json 2>&1) || true
  if echo "$RESP" | grep -q '"ok":true'; then
    echo "gemini_cli 调用成功（输出中曾返回 ok:true）。"
  else
    echo "gemini_cli 调用可能未成功或未使用该工具，请检查 openclaw 与模型配置。输出片段:"
    echo "$RESP" | head -20
  fi
else
  echo "未检测到 gemini，跳过 agent 调用验证。安装后可用：brew install gemini-cli"
fi

echo "验证完成。"
