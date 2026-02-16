# OpenClaw MEMORY 机制总结

> 更新日期: 2026-02-16
> 版本: v2（新增 QMD 远程模式集成）

---

## 一、架构概览

OpenClaw 提供两种可切换的 Memory 后端，均基于**百炼远程模型**（无本地大模型依赖）：

```
┌──────────────────────────────────────────────────────────────┐
│                    openclaw.json 配置                         │
│  memory.backend = "builtin" | "qmd"                          │
└────────────────────┬─────────────────────────────────────────┘
                     │
          ┌──────────┴──────────┐
          ▼                     ▼
  ┌───────────────┐     ┌──────────────┐
  │   Builtin     │     │   QMD 远程    │
  │   后端        │     │   后端        │
  ├───────────────┤     ├──────────────┤
  │ SQLite + FTS5 │     │ SQLite + FTS5│
  │ BM25 搜索     │     │ BM25 搜索    │
  │ text-embedding│     │ text-embedding│
  │   -v4 (向量)  │     │   -v4 (向量) │
  │ gte-rerank    │     │ gte-rerank   │
  │   (可选重排)  │     │   (默认重排) │
  └───────────────┘     └──────────────┘
          │                     │
          └──────────┬──────────┘
                     ▼
         ┌───────────────────┐
         │  百炼 DashScope   │
         │  远程 API 服务     │
         │  (无本地模型)      │
         └───────────────────┘
```

---

## 二、两种后端详解

### 2.1 Builtin 后端（OpenClaw 原生）

**搜索管线**：BM25 关键词 → 向量相似度 → 加权合并 → [rerank 精排]

- **存储引擎**: SQLite + sqlite-vec + FTS5
- **嵌入模型**: text-embedding-v4（DashScope OpenAI 兼容 API）
- **重排模型**: gte-rerank（DashScope 原生 API，可选启用）
- **混合搜索**: BM25 (textWeight=0.3) + 向量 (vectorWeight=0.7)
- **代码路径**: `openclaw-src/src/memory/manager.ts`

#### 配置示例
```json
{
  "memory": { "backend": "builtin" },
  "agents": {
    "defaults": {
      "memorySearch": {
        "provider": "openai",
        "model": "text-embedding-v4",
        "remote": {
          "baseUrl": "https://dashscope.aliyuncs.com/compatible-mode/v1",
          "apiKey": "${DASHSCOPE_API_KEY}"
        },
        "query": {
          "rerank": {
            "enabled": true,
            "baseUrl": "https://dashscope.aliyuncs.com/api/v1/services/rerank/text-rerank/text-rerank",
            "apiKey": "${DASHSCOPE_API_KEY}",
            "model": "gte-rerank",
            "topN": 5
          }
        }
      }
    }
  }
}
```

### 2.2 QMD 远程后端

**搜索管线**（query 模式）：查询扩展 → BM25 + 向量 → 合并去重 → rerank 精排

- **引擎**: QMD (Quantum Memory Drive) CLI 工具
- **嵌入模型**: text-embedding-v4（通过 `QMD_LLM_PROVIDER=remote` 激活）
- **重排模型**: gte-rerank（DashScope 原生 API）
- **查询扩展**: 启发式扩展（不使用本地 LLM）
- **代码路径**: `qmd/src/remote-llm.ts` + `openclaw-src/src/memory/qmd-manager.ts`

#### 搜索模式

| 模式 | 命令 | 管线 | Token 消耗 |
|------|------|------|-----------|
| `search` | `qmd search` | BM25 纯关键词 | 0 |
| `vsearch` | `qmd vsearch` | 查询扩展 + 向量搜索 | ~6 embed |
| `query` | `qmd query` | BM25 + 向量 + rerank | ~6 embed + ~140 rerank |

#### 配置示例
```json
{
  "env": {
    "vars": {
      "QMD_LLM_PROVIDER": "remote",
      "QMD_API_KEY": "${DASHSCOPE_API_KEY}",
      "QMD_EMBED_MODEL": "text-embedding-v4",
      "QMD_EMBED_BASE_URL": "https://dashscope.aliyuncs.com/compatible-mode/v1",
      "QMD_RERANK_MODEL": "gte-rerank",
      "QMD_RERANK_BASE_URL": "https://dashscope.aliyuncs.com/api/v1/services/rerank/text-rerank/text-rerank"
    }
  },
  "memory": {
    "backend": "qmd",
    "qmd": {
      "searchMode": "query",
      "includeDefaultMemory": true,
      "limits": { "maxResults": 6, "timeoutMs": 15000 }
    }
  }
}
```

---

## 三、性能对比测试

> 测试日期: 2026-02-16
> 测试数据: 1 个 Markdown 文件 (22 行, ~910 B)
> 5 个测试查询（中文）

### 3.1 搜索质量（Score）

| 查询 | Builtin (embed) | QMD vsearch | QMD query (rerank) |
|------|-----------------|-------------|-------------------|
| qwen-max 模型升级 | 0.675 | 0.57 | **0.91** |
| 编程语言 TypeScript Python | 0.508 | 0.35 | **0.88** |
| 飞书浏览器 | 0.356 | 0.52 | **0.89** |
| DashScope 百炼 text-embedding | 0.648 | 0.44 | **0.90** |
| 天气预报 (不相关) | 无匹配 | 0.38 | **0.76** |

### 3.2 响应时间

| 后端 | 搜索模式 | 平均耗时 |
|------|---------|---------|
| Builtin | embed only | ~400ms |
| Builtin | embed + rerank | ~700ms |
| QMD | BM25 (search) | ~550ms |
| QMD | 向量 (vsearch) | ~1.0s |
| QMD | 完整管线 (query) | **~1.1s** |

### 3.3 Token 消耗（重点）

| 操作 | 每次搜索 Embed Tokens | 每次搜索 Rerank Tokens | 总 Tokens/次 |
|------|----------------------|----------------------|-------------|
| Builtin (仅向量) | ~6 | 0 | **~6** |
| Builtin + Rerank | ~6 | ~135 | **~141** |
| QMD search (BM25) | 0 | 0 | **0** |
| QMD vsearch | ~6 | 0 | **~6** |
| QMD query | ~6 | ~135 | **~141** |

#### Token 成本估算

| 使用量 | Embedding 成本 | Rerank 成本 | 合计 |
|--------|---------------|-------------|------|
| 100 次/天 | 600 tokens × ¥0.0007/千token = **¥0.0004** | 13,500 tokens × ¥0.0005/千token = **¥0.007** | **¥0.007/天** |
| 1,000 次/天 | **¥0.004** | **¥0.068** | **¥0.07/天** |
| 10,000 次/天 | **¥0.042** | **¥0.675** | **¥0.72/天** |

**结论：Token 成本极低，即使每天 10,000 次搜索，成本不到 1 元人民币。**

---

## 四、切换方法

### 方法 1：使用切换脚本

```bash
# 切换到 Builtin
bash doc/scripts/memory-switch.sh builtin

# 切换到 QMD
bash doc/scripts/memory-switch.sh qmd

# 切换并重启 gateway
bash doc/scripts/memory-switch.sh qmd --restart
```

### 方法 2：手动修改配置

编辑 `~/.openclaw/openclaw.json`：

```json
{
  "memory": {
    "backend": "builtin"  // 或 "qmd"
  }
}
```

然后重启：`openclaw gateway restart`

### 方法 3：CLI 命令

```bash
openclaw config set memory.backend builtin   # 切换到 Builtin
openclaw config set memory.backend qmd       # 切换到 QMD
openclaw gateway restart
```

---

## 五、技术实现细节

### 5.1 QMD 远程模式补丁

QMD 原生只支持本地 GGUF 模型。通过以下修改实现远程 API 支持：

| 文件 | 修改 |
|------|------|
| `qmd/src/remote-llm.ts` | **新建** — DashScopeRemoteLLM 类，实现 LLM 接口 |
| `qmd/src/llm.ts` | 修改 `getDefaultLlamaCpp()` 支持 `QMD_LLM_PROVIDER=remote` |
| `qmd/src/qmd.ts` | 添加远程模块预加载 (`ensureRemoteLlmLoaded()`) |

**环境变量驱动**：通过 `QMD_LLM_PROVIDER=remote` 激活远程模式，所有其他配置通过环境变量传递。

### 5.2 Builtin Rerank 扩展

OpenClaw Builtin 后端新增了 reranking 支持：

| 文件 | 修改 |
|------|------|
| `openclaw-src/src/config/types.tools.ts` | 新增 `query.rerank` 类型定义 |
| `openclaw-src/src/config/zod-schema.agent-runtime.ts` | 新增 rerank Schema 验证 |
| `openclaw-src/src/agents/memory-search.ts` | 新增 rerank 配置解析和默认值 |
| `openclaw-src/src/memory/reranker.ts` | **新建** — DashScope Rerank API 调用 |
| `openclaw-src/src/memory/manager.ts` | 在 search() 中集成 applyRerank() |

### 5.3 DashScope API 端点

| 功能 | 端点 | 模型 |
|------|------|------|
| Embedding | `https://dashscope.aliyuncs.com/compatible-mode/v1/embeddings` | text-embedding-v4 |
| Reranking | `https://dashscope.aliyuncs.com/api/v1/services/rerank/text-rerank/text-rerank` | gte-rerank |

---

## 六、推荐方案

### 日常使用推荐：Builtin + Rerank

- 响应快（~700ms）
- 搜索质量高（含 rerank）
- 配置简单（已内置在 OpenClaw 中）
- Token 成本极低

### 高级场景推荐：QMD query 模式

适合以下场景：
- 需要更丰富的搜索管线（查询扩展 + 多路召回 + rerank）
- 需要文件级管理和上下文标注
- 需要增量索引和集合管理
- 未来可扩展为 MCP daemon 常驻服务

---

## 七、脚本清单

| 脚本 | 路径 | 用途 |
|------|------|------|
| 后端切换 | `doc/scripts/memory-switch.sh` | 在 builtin/qmd 之间切换 |
| QMD 设置 | `doc/scripts/qmd-remote-setup.sh` | QMD 远程模式初始化与索引重建 |
| 性能测试 | `doc/scripts/memory-benchmark.sh` | 两种后端性能对比测试 |

---

## 八、相关文档

| 文档 | 路径 | 内容 |
|------|------|------|
| 默认机制与切换验证 | `doc/sum/MEMORY默认机制与切换验证.md` | 默认是哪种、当前用的是哪种、如何验证、如何切换、如何确认回答按所选方式执行 |
| 实现原理与案例 | `doc/sum/MEMORY机制实现原理.md` | BM25/向量/Rerank 原理、Builtin/QMD 管线、端到端案例与 Token 数据 |
| 切换与验证命令速查 | `doc/scripts/memory-切换与验证命令.md` | 查看后端、切换、验证的完整命令与流程 |
