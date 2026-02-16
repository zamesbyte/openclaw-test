#!/bin/bash
# =============================================================================
# Memory Backend Switch Script
# 在 OpenClaw 原生 Builtin 后端和 QMD 远程后端之间切换
#
# 用法：从任意目录执行均可（使用 $HOME/.openclaw/openclaw.json）
#   bash doc/scripts/memory-switch.sh builtin
#   bash doc/scripts/memory-switch.sh qmd
#   bash /path/to/openclaw/doc/scripts/memory-switch.sh qmd --restart
# =============================================================================

set -euo pipefail

CONFIG_FILE="${OPENCLAW_CONFIG:-$HOME/.openclaw/openclaw.json}"
USAGE="Usage: $0 <builtin|qmd> [--restart]

  builtin  - 使用 OpenClaw 原生内存后端 (BM25 + text-embedding-v4 + gte-rerank)
  qmd      - 使用 QMD 远程后端 (BM25 + text-embedding-v4 + gte-rerank)
  
  --restart  可选，自动重启 OpenClaw gateway
  
示例:
  $0 builtin          # 切换到 Builtin 后端
  $0 qmd              # 切换到 QMD 后端
  $0 qmd --restart    # 切换到 QMD 并重启 gateway
"

if [ $# -lt 1 ]; then
  echo "$USAGE"
  exit 1
fi

BACKEND="$1"
RESTART="${2:-}"

if [ "$BACKEND" != "builtin" ] && [ "$BACKEND" != "qmd" ]; then
  echo "Error: Invalid backend '$BACKEND'. Use 'builtin' or 'qmd'."
  echo ""
  echo "$USAGE"
  exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Config file not found: $CONFIG_FILE"
  exit 1
fi

echo "Switching memory backend to: $BACKEND"

# 使用 python3 修改 JSON 配置
python3 -c "
import json
with open('$CONFIG_FILE', 'r') as f:
    cfg = json.load(f)

cfg.setdefault('memory', {})
cfg['memory']['backend'] = '$BACKEND'

with open('$CONFIG_FILE', 'w') as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
    f.write('\n')

print(f'Updated memory.backend = \"$BACKEND\" in {repr(\"$CONFIG_FILE\")}')
"

# 如果切换到 QMD 且索引不存在，提示重建
if [ "$BACKEND" = "qmd" ]; then
  INDEX_PATH="$HOME/.openclaw/agents/main/qmd/xdg-cache/qmd/index.sqlite"
  if [ ! -f "$INDEX_PATH" ]; then
    echo ""
    echo "Warning: QMD index not found. Run the following to build:"
    echo "  export QMD_LLM_PROVIDER=remote"
    echo "  export QMD_API_KEY=\$DASHSCOPE_API_KEY"
    echo "  qmd update && qmd embed -f"
  else
    echo "QMD index found at: $INDEX_PATH"
  fi
fi

if [ "$RESTART" = "--restart" ]; then
  echo ""
  echo "Restarting OpenClaw gateway..."
  openclaw gateway restart 2>/dev/null || echo "Note: gateway restart requires openclaw CLI"
fi

echo ""
echo "Done. Current memory backend: $BACKEND"
echo ""
echo "--- 两种后端对比 ---"
echo "  builtin: BM25 + text-embedding-v4 (向量) + gte-rerank (可选)"
echo "     - 搜索耗时: ~400ms (仅 embed) / ~700ms (含 rerank)"
echo "     - Token/次: ~6 (embed) + ~140 (rerank) = ~146"
echo ""
echo "  qmd:     BM25 + text-embedding-v4 (向量) + gte-rerank (query 模式)"
echo "     - 搜索耗时: ~1s (query 模式)"
echo "     - Token/次: ~6 (embed) + ~140 (rerank) ≈ ~146"
echo "     - 搜索质量: Score 0.76-0.91 (含 rerank 排序)"
echo ""
echo "验证当前配置: jq -r '.memory.backend // \"builtin\"' $CONFIG_FILE"
