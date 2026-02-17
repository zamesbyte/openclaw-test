#!/bin/bash
# =============================================================================
# Memory Backend Benchmark Script
# 对比 OpenClaw Builtin 后端 vs QMD 远程模式后端
# 特别关注: 搜索质量、响应时间、Token 消耗
# =============================================================================

set -euo pipefail

# --- 配置 ---
API_KEY="sk-251fedca99184f2ea8c0b32ea371f5e7"
EMBED_BASE_URL="https://dashscope.aliyuncs.com/compatible-mode/v1"
EMBED_MODEL="text-embedding-v4"
RERANK_BASE_URL="https://dashscope.aliyuncs.com/api/v1/services/rerank/text-rerank/text-rerank"
RERANK_MODEL="gte-rerank"

# QMD 环境变量
export PATH="$HOME/.bun/bin:$PATH"
export QMD_LLM_PROVIDER=remote
export QMD_API_KEY="$API_KEY"
export QMD_EMBED_MODEL="$EMBED_MODEL"
export QMD_EMBED_BASE_URL="$EMBED_BASE_URL"
export QMD_RERANK_MODEL="$RERANK_MODEL"
export QMD_RERANK_BASE_URL="$RERANK_BASE_URL"
export XDG_CONFIG_HOME=~/.openclaw/agents/main/qmd/xdg-config
export XDG_CACHE_HOME=~/.openclaw/agents/main/qmd/xdg-cache

# 测试查询
QUERIES=(
  "qwen-max 模型升级"
  "编程语言 TypeScript Python"
  "飞书浏览器"
  "DashScope 百炼 text-embedding"
  "天气预报"
)

RESULT_FILE="/tmp/memory_benchmark_$(date +%Y%m%d_%H%M%S).md"

echo "# Memory Backend Benchmark Results" > "$RESULT_FILE"
echo "" >> "$RESULT_FILE"
echo "> Date: $(date '+%Y-%m-%d %H:%M:%S')" >> "$RESULT_FILE"
echo "" >> "$RESULT_FILE"

# =============================================================================
# 1. Builtin 后端测试 (Embedding only, no rerank)
# =============================================================================
echo "## 1. Builtin 后端 (BM25 + text-embedding-v4)" >> "$RESULT_FILE"
echo "" >> "$RESULT_FILE"
echo "| # | 查询 | 耗时 | Embed Tokens |" >> "$RESULT_FILE"
echo "|---|------|------|-------------|" >> "$RESULT_FILE"

echo "=== Testing Builtin Backend (embedding API calls) ==="
BUILTIN_TOTAL_TOKENS=0

for i in "${!QUERIES[@]}"; do
  q="${QUERIES[$i]}"
  echo "  Query $((i+1)): $q"
  
  # 调用 DashScope embedding API 并计算 token
  START_MS=$(python3 -c "import time; print(int(time.time()*1000))")
  EMBED_RESULT=$(curl -s -X POST "$EMBED_BASE_URL/embeddings" \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"model\": \"$EMBED_MODEL\", \"input\": \"$q\"}" 2>&1)
  END_MS=$(python3 -c "import time; print(int(time.time()*1000))")
  
  ELAPSED=$((END_MS - START_MS))
  TOKENS=$(echo "$EMBED_RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('usage',{}).get('total_tokens',0))" 2>/dev/null || echo "0")
  BUILTIN_TOTAL_TOKENS=$((BUILTIN_TOTAL_TOKENS + TOKENS))
  
  echo "| $((i+1)) | \`$q\` | ${ELAPSED}ms | $TOKENS |" >> "$RESULT_FILE"
done

echo "" >> "$RESULT_FILE"
echo "**Builtin 总 Embedding Tokens: $BUILTIN_TOTAL_TOKENS**" >> "$RESULT_FILE"
echo "**注**: Builtin 后端搜索时仅需 1 次 embedding API 调用(query embedding)" >> "$RESULT_FILE"
echo "" >> "$RESULT_FILE"

# =============================================================================
# 2. Builtin + Rerank 测试
# =============================================================================
echo "## 2. Builtin + Rerank (BM25 + text-embedding-v4 + gte-rerank)" >> "$RESULT_FILE"
echo "" >> "$RESULT_FILE"
echo "| # | 查询 | Embed Tokens | Rerank Tokens | 总 Tokens |" >> "$RESULT_FILE"
echo "|---|------|-------------|---------------|-----------|" >> "$RESULT_FILE"

echo ""
echo "=== Testing Builtin + Rerank ==="
BUILTIN_RERANK_TOTAL=0

for i in "${!QUERIES[@]}"; do
  q="${QUERIES[$i]}"
  echo "  Query $((i+1)): $q"
  
  # Embedding
  EMBED_RESULT=$(curl -s -X POST "$EMBED_BASE_URL/embeddings" \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"model\": \"$EMBED_MODEL\", \"input\": \"$q\"}" 2>&1)
  E_TOKENS=$(echo "$EMBED_RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('usage',{}).get('total_tokens',0))" 2>/dev/null || echo "0")
  
  # Rerank (simulated with 5 documents)
  RERANK_RESULT=$(curl -s -X POST "$RERANK_BASE_URL" \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    -d "{
      \"model\": \"$RERANK_MODEL\",
      \"input\": {
        \"query\": \"$q\",
        \"documents\": [
          \"将默认模型从 qwen-plus 升级为 qwen-max，解决了 tool calling 不稳定的问题\",
          \"配置了百炼 text-embedding-v4 作为 memory search 的 embedding 模型\",
          \"修复了飞书浏览器工具调用的三个连环问题\",
          \"用户使用飞书作为主要通信渠道\",
          \"常用编程语言：TypeScript、Python\"
        ]
      },
      \"parameters\": {\"top_n\": 3, \"return_documents\": false}
    }" 2>&1)
  R_TOKENS=$(echo "$RERANK_RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('usage',{}).get('total_tokens',0))" 2>/dev/null || echo "0")
  
  TOTAL=$((E_TOKENS + R_TOKENS))
  BUILTIN_RERANK_TOTAL=$((BUILTIN_RERANK_TOTAL + TOTAL))
  
  echo "| $((i+1)) | \`$q\` | $E_TOKENS | $R_TOKENS | $TOTAL |" >> "$RESULT_FILE"
done

echo "" >> "$RESULT_FILE"
echo "**Builtin+Rerank 总 Tokens: $BUILTIN_RERANK_TOTAL** (Embed + Rerank)" >> "$RESULT_FILE"
echo "" >> "$RESULT_FILE"

# =============================================================================
# 3. QMD 远程模式测试
# =============================================================================
echo "## 3. QMD 远程模式 (BM25 + text-embedding-v4 + gte-rerank)" >> "$RESULT_FILE"
echo "" >> "$RESULT_FILE"

echo ""
echo "=== Testing QMD Remote Mode ==="

# QMD search mode
echo "### 3.1 QMD search (BM25 only)" >> "$RESULT_FILE"
echo "" >> "$RESULT_FILE"
echo "| # | 查询 | 耗时 | 命中 | Tokens |" >> "$RESULT_FILE"
echo "|---|------|------|------|--------|" >> "$RESULT_FILE"

for i in "${!QUERIES[@]}"; do
  q="${QUERIES[$i]}"
  echo "  BM25 search: $q"
  
  START_MS=$(python3 -c "import time; print(int(time.time()*1000))")
  RESULT=$(qmd search "$q" --json 2>/dev/null)
  END_MS=$(python3 -c "import time; print(int(time.time()*1000))")
  
  ELAPSED=$((END_MS - START_MS))
  HIT=$(echo "$RESULT" | python3 -c "import sys,json; r=json.load(sys.stdin); print(len(r))" 2>/dev/null || echo "0")
  
  echo "| $((i+1)) | \`$q\` | ${ELAPSED}ms | $HIT | 0 |" >> "$RESULT_FILE"
done

echo "" >> "$RESULT_FILE"
echo "**BM25 Tokens: 0** (无模型调用)" >> "$RESULT_FILE"
echo "" >> "$RESULT_FILE"

# QMD vsearch mode
echo "### 3.2 QMD vsearch (向量搜索)" >> "$RESULT_FILE"
echo "" >> "$RESULT_FILE"
echo "| # | 查询 | 耗时 | Score | " >> "$RESULT_FILE"
echo "|---|------|------|-------|" >> "$RESULT_FILE"

QMD_VSEARCH_TOTAL=0
for i in "${!QUERIES[@]}"; do
  q="${QUERIES[$i]}"
  echo "  vsearch: $q"
  
  START_MS=$(python3 -c "import time; print(int(time.time()*1000))")
  RESULT=$(qmd vsearch "$q" --json 2>/dev/null)
  END_MS=$(python3 -c "import time; print(int(time.time()*1000))")
  
  ELAPSED=$((END_MS - START_MS))
  SCORE=$(echo "$RESULT" | python3 -c "import sys,json; r=json.load(sys.stdin); print(r[0]['score'] if r else 'N/A')" 2>/dev/null || echo "N/A")
  
  echo "| $((i+1)) | \`$q\` | ${ELAPSED}ms | $SCORE |" >> "$RESULT_FILE"
done

echo "" >> "$RESULT_FILE"

# QMD query mode (full pipeline)
echo "### 3.3 QMD query (BM25 + vector + rerank)" >> "$RESULT_FILE"
echo "" >> "$RESULT_FILE"
echo "| # | 查询 | 耗时 | Score |" >> "$RESULT_FILE"
echo "|---|------|------|-------|" >> "$RESULT_FILE"

for i in "${!QUERIES[@]}"; do
  q="${QUERIES[$i]}"
  echo "  query: $q"
  
  START_MS=$(python3 -c "import time; print(int(time.time()*1000))")
  RESULT=$(qmd query "$q" --json 2>/dev/null)
  END_MS=$(python3 -c "import time; print(int(time.time()*1000))")
  
  ELAPSED=$((END_MS - START_MS))
  SCORE=$(echo "$RESULT" | python3 -c "import sys,json; r=json.load(sys.stdin); print(r[0]['score'] if r else 'N/A')" 2>/dev/null || echo "N/A")
  
  echo "| $((i+1)) | \`$q\` | ${ELAPSED}ms | $SCORE |" >> "$RESULT_FILE"
done

echo "" >> "$RESULT_FILE"

# =============================================================================
# Summary
# =============================================================================
echo "## 4. 总结" >> "$RESULT_FILE"
echo "" >> "$RESULT_FILE"
echo "| 方案 | 每次搜索 Embed Tokens | 每次搜索 Rerank Tokens | 额外 Token |" >> "$RESULT_FILE"
echo "|------|----------------------|----------------------|-----------|" >> "$RESULT_FILE"
echo "| Builtin (BM25+向量) | ~5-10 (query embed) | 0 | 0 |" >> "$RESULT_FILE"
echo "| Builtin+Rerank | ~5-10 (query embed) | ~150-250 (per rerank) | 0 |" >> "$RESULT_FILE"
echo "| QMD search (BM25) | 0 | 0 | 0 |" >> "$RESULT_FILE"
echo "| QMD vsearch | ~5-10 (query embed) | 0 | ~20-50 (query expansion) |" >> "$RESULT_FILE"
echo "| QMD query | ~5-10 (query embed) | ~150-250 (rerank) | ~20-50 (query expansion) |" >> "$RESULT_FILE"
echo "" >> "$RESULT_FILE"

echo ""
echo "=== Benchmark Complete ==="
echo "Results saved to: $RESULT_FILE"
cat "$RESULT_FILE"
