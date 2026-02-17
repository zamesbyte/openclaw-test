#!/bin/bash
# =============================================================================
# QMD Remote Mode Setup Script
# 配置 QMD 使用百炼远程模型（text-embedding-v4 + gte-rerank）
# 替代本地 GGUF 模型方案，不下载任何本地大模型
# =============================================================================

set -euo pipefail

echo "=== QMD Remote Mode Setup ==="
echo ""

# --- 检查依赖 ---
if ! command -v bun &>/dev/null; then
  echo "Installing Bun runtime..."
  curl -fsSL https://bun.sh/install | bash
  export PATH="$HOME/.bun/bin:$PATH"
fi

if ! command -v qmd &>/dev/null; then
  echo "Installing QMD CLI..."
  bun install -g https://github.com/tobi/qmd
fi

echo "Bun: $(bun --version)"
echo "QMD: $(qmd --version 2>/dev/null || echo 'installed')"
echo ""

# --- 配置环境变量 ---
API_KEY="${DASHSCOPE_API_KEY:-${QMD_API_KEY:-}}"
if [ -z "$API_KEY" ]; then
  echo "Error: DASHSCOPE_API_KEY or QMD_API_KEY must be set"
  echo "  export DASHSCOPE_API_KEY=sk-xxxxx"
  exit 1
fi

export QMD_LLM_PROVIDER=remote
export QMD_API_KEY="$API_KEY"
export QMD_EMBED_MODEL="${QMD_EMBED_MODEL:-text-embedding-v4}"
export QMD_EMBED_BASE_URL="${QMD_EMBED_BASE_URL:-https://dashscope.aliyuncs.com/compatible-mode/v1}"
export QMD_RERANK_MODEL="${QMD_RERANK_MODEL:-gte-rerank}"
export QMD_RERANK_BASE_URL="${QMD_RERANK_BASE_URL:-https://dashscope.aliyuncs.com/api/v1/services/rerank/text-rerank/text-rerank}"

# OpenClaw QMD 目录
QMD_DIR="${HOME}/.openclaw/agents/main/qmd"
export XDG_CONFIG_HOME="${QMD_DIR}/xdg-config"
export XDG_CACHE_HOME="${QMD_DIR}/xdg-cache"

echo "Configuration:"
echo "  Provider: remote (DashScope)"
echo "  Embed Model: $QMD_EMBED_MODEL"
echo "  Rerank Model: $QMD_RERANK_MODEL"
echo "  XDG_CONFIG: $XDG_CONFIG_HOME"
echo "  XDG_CACHE:  $XDG_CACHE_HOME"
echo ""

# --- 确保 remote-llm.ts 已安装 ---
QMD_SRC="$(bun pm ls -g 2>/dev/null | grep qmd | head -1 | awk '{print $NF}')/src" || true
if [ -z "$QMD_SRC" ]; then
  QMD_SRC="$HOME/.bun/install/global/node_modules/@tobilu/qmd/src"
fi

if [ ! -f "$QMD_SRC/remote-llm.ts" ]; then
  echo "Error: remote-llm.ts not found at $QMD_SRC/"
  echo "Please install the QMD remote LLM patch first."
  exit 1
fi
echo "QMD source: $QMD_SRC"
echo "remote-llm.ts: OK"
echo ""

# --- 重建索引 ---
echo "=== Rebuilding Index ==="
echo "Updating collections..."
qmd update 2>&1 | tail -5

echo ""
echo "Building vector embeddings with $QMD_EMBED_MODEL..."
qmd embed -f 2>&1 | tail -5

echo ""
echo "=== Verification ==="
echo "Status:"
qmd status 2>&1 | head -15

echo ""
echo "Test search (query mode):"
qmd query "测试搜索" --json 2>&1 | head -20

echo ""
echo "=== Setup Complete ==="
echo ""
echo "To use QMD remote mode in OpenClaw, add to openclaw.json:"
echo '  "memory": { "backend": "qmd" }'
echo ""
echo "Or use the switch script:"
echo "  bash doc/scripts/memory-switch.sh qmd --restart"
