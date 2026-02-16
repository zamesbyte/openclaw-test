# OpenClaw MEMORY 机制实现原理详解

> 面向零基础读者 · 含案例与测试数据
> 更新日期: 2026-02-16

本文用**通俗语言 + 真实案例**说明 OpenClaw 几种 MEMORY 机制是怎么工作的，以及为什么会有不同的搜索质量和 Token 消耗。

---

## 阅读指引（没有基础可以从这里开始）

- **只想知道「选哪种」**：直接看 **第五节「总结：一眼看懂该选谁」**。
- **想理解「记忆是怎么被搜到的」**：从 **第一节** 看概念，再读 **第二节 Builtin** 的「索引流程」和「搜索管线」。
- **想搞清「QMD 三种模式差别」**：看 **第三节**，用同一句查询「qwen-max 模型」对比 search / vsearch / query。
- **想对几种机制并排比较**：看 **第四节** 的管线和测试数据表。

全文使用的**真实测试环境**：一个 Markdown 文件 `2026-02-16.md`（约 22 行），内含「qwen-max 升级、text-embedding-v4、飞书浏览器」等句子；所有分数、耗时、Token 均来自该环境下的实测或接口估算。

---

## 一、先搞懂几个核心概念

### 1.1 记忆（Memory）在这里指什么？

在 OpenClaw 里，**Memory** 不是「对话历史」，而是**可被搜索的文档库**：  
你把 Markdown 笔记、配置记录、项目说明等放进指定目录，系统会对它们建索引；当用户提问时，系统会**先搜这些文档**，把相关片段塞进上下文，再让大模型回答。  
所以「MEMORY 机制」= **「怎么建索引 + 怎么搜」** 的一整套实现。

### 1.2 为什么要多种搜索方式？

一句话概括：

- **关键词搜索**：像 Ctrl+F，找「字面匹配」，快、省资源，但对同义词、换说法不敏感。
- **向量搜索**：把句子变成一串数字（向量），按「意思是否相近」找，能抓住语义，但需要调用模型算向量，有延迟和 Token 消耗。
- **Rerank（精排）**：在已经搜出一批候选后，再用一个专门模型对「查询 vs 每一条候选」打分，把最相关的一条排到最前，提高 Top1 准确率。

**用生活例子理解：**

- **关键词**：像在书里搜「北京」——只有写了两字的页会出来，写「首都」的页搜不到。
- **向量**：像「按主题找段落」——问「北京有什么好吃的」，模型把问题和每段话都变成一组数字，数字接近的段落（主题接近）会被找出来，即使用词不同。
- **Rerank**：像「老师批卷」——已经筛出了 5 段可能相关的段落，Rerank 模型再逐段看「这段是不是在回答这个问题」，给每段打 0~1 分，最后按分数排顺序。

下面分别说清楚每一种在 OpenClaw 里是怎么实现的，以及用测试数据举例。

---

## 二、Builtin 后端：实现原理与案例

Builtin 是 OpenClaw **自带的**记忆后端，所有逻辑都在 OpenClaw 代码里，不依赖外部搜索服务。

### 2.1 数据是怎么存进去的？（索引流程）

整体流程可以简化为：

```
Markdown 文件 → 按块切分（chunk）→ 每块文本 → 调用百炼 API 得到向量 → 写入 SQLite
                    ↓
              同时把原文放进 FTS5 全文索引（供 BM25 用）
```

**要点：**

1. **分块（Chunking）**  
   一个文件不会整篇当成一条记录，而是按「块」切（例如每块约 400 token，块与块之间重叠约 80 token）。这样搜索时返回的是「某一段」，而不是整篇，更精准。

2. **两套存储**  
   - **FTS5 表**：存的是「原文」，用于关键词搜索（BM25）。  
   - **向量表**：存的是「每块文本对应的向量」，用于相似度搜索。向量由百炼 **text-embedding-v4** 生成（OpenAI 兼容接口），维度 1024。

3. **何时算向量？**  
   在索引（同步）阶段，对每个块调用一次 Embedding API，得到向量后写入 SQLite，并带上是哪个模型生成的（如 `text-embedding-v4`），以便后续搜索时只和同模型向量比较。

**小案例（对应真实测试环境）：**  
测试里用了一个文件 `2026-02-16.md`（约 22 行）。索引后：1 个文件 → 1 个 chunk → 1 条向量记录。  
所以 Builtin 状态里会看到：`Indexed: 1/1 files · 1 chunks`，`Vector dims: 1024`。

### 2.2 搜索时具体做了什么？（Builtin 搜索管线）

用户输入一个查询，例如：**「qwen-max 模型升级」**。Builtin 的搜索管线是（与代码一致）：

```
步骤 1：关键词搜索（BM25）
步骤 2：向量搜索（用查询的向量和库里向量算相似度）
步骤 3：混合合并（给两种分数加权，得到最终排序）
步骤 4：（可选）Rerank 精排
```

下面按步骤说明，并配上测试数据。

#### 步骤 1：BM25 关键词搜索

- **做什么**：把查询拆成「词」（Builtin 里用正则取英文、数字等，中文会受限于分词），在 FTS5 里做全文匹配，用 SQLite 的 `bm25()` 得到每条匹配的 **rank**（越小越相关）。
- **代码里**：`buildFtsQuery("qwen-max 模型升级")` 会得到类似 `"qwen" AND "max"` 的 FTS 查询（中文可能被忽略），在 `documents_fts` 表上执行 `WHERE documents_fts MATCH ? ORDER BY rank ASC`。
- **分数转换**：`bm25RankToScore(rank) = 1 / (1 + rank)`，把 rank 变成 0~1 的 **textScore**。  
- **测试中的表现**：对「qwen-max 模型升级」这种中英混合，BM25 可能命中到含 "qwen"、"max" 的块，也可能因为中文没分词而命中很少。所以**单靠 BM25 时，Builtin 的分数是 0.675**（来自后续和向量合并后的结果；纯 BM25 对中文较弱）。

#### 步骤 2：向量搜索

- **做什么**：  
  1. 用**同一个查询**「qwen-max 模型升级」调用百炼 **text-embedding-v4**，得到查询向量（1024 维）。  
  2. 在 SQLite 的向量表里，用 **余弦相似度**（cosine）比较查询向量和每条已存向量，按相似度从高到低排序，取前 N 条（N 由 `candidateMultiplier * maxResults` 等配置决定）。  
- **代码里**：  
  - 先 `embedQueryWithTimeout(cleaned)` 得到 `queryVec`。  
  - 再 `searchVector(queryVec, candidates)`，内部执行类似  
    `vec_distance_cosine(v.embedding, ?) AS dist ... ORDER BY dist ASC`，  
    然后把 `dist` 转成 `score = 1 - dist`（距离越小，分数越高）。  
- **测试数据**：同一查询下，向量搜索能抓到「升级 qwen-max」「配置模型」等语义，所以**向量这边会给这一块较高的 vectorScore**。  
  合并前，单路向量结果就足以让这条记忆的**综合分数达到 0.675**（和 BM25 一起加权后的结果）。

#### 步骤 3：混合合并（Hybrid Merge）

- **做什么**：同一条 chunk 可能既被 BM25 命中，又被向量命中。需要把两种分数合成一个最终分数。  
- **公式**（与 `hybrid.ts` 一致）：  
  `score = vectorWeight * vectorScore + textWeight * textScore`  
  默认 `vectorWeight = 0.7`，`textWeight = 0.3`。  
- **去重**：按 chunk `id` 合并，同一 chunk 只保留一条，用上面的公式算一个 score，然后**按 score 降序**排序，再按 `minScore` 过滤、取前 `maxResults` 条。  
- **案例**：  
  - 若某块 vectorScore=0.8，textScore=0.4，则  
    `score = 0.7*0.8 + 0.3*0.4 = 0.56 + 0.12 = 0.68`。  
  这和你看到的 **0.675** 非常接近，说明测试里这条记忆在「qwen-max 模型升级」上，向量和关键词都给了不错的分，合并后约 0.675。

#### 步骤 4：Rerank 精排（可选）

- **做什么**：混合排序后，如果开启了 `query.rerank`，会把当前**前若干条候选**（每条用其 `snippet` 文本）再发给百炼 **gte-rerank** 接口，让专门的重排模型对「查询 + 候选列表」重新打分。  
- **接口**：  
  - 请求体里是 `query` + `documents`（字符串数组），  
  - 返回每条文档的 `relevance_score`（0~1）。  
- **代码里**：`applyRerank(query, filtered, rerankCfg)` 把 `filtered` 转成 `{ id, text }[]`，调用 `rerankDocuments`，再按返回的 `relevance_score` 重排并截断为 `topN`。  
- **测试数据**：  
  - 同一查询「qwen-max 模型配置」在 **仅 Builtin 混合** 时，Top1 分数约 0.675；  
  - **加上 Rerank** 后，Top1 的 relevance_score 可以到 **0.779**，且排序更符合语义（例如「将默认模型从 qwen-plus 升级为 qwen-max…」会排第一）。  
  所以 Rerank 的作用是：**在已有候选里，把「最贴题」的那一条推到最前**，提高首条命中质量。

### 2.3 Builtin 的 Token 消耗从哪里来？（结合测试数据）

- **Embedding**：每次搜索只算**一次**「查询」的向量。测试里 5 个查询，总 Embedding Tokens ≈ 29（平均每次约 6 token）。  
- **Rerank**：若开启，每次搜索会把「查询 + 若干条候选 snippet」发给 gte-rerank。测试里 5 次 Rerank 总 Tokens ≈ 675，平均每次约 135。  
- **合计**：  
  - 仅向量：约 **6 token/次**。  
  - 向量 + Rerank：约 **6 + 135 = 141 token/次**。  
  这就是你在「Token 消耗对比」里看到 Builtin 数字的来源。

### 2.4 小结：Builtin 一句话 + 数据

- **实现**：SQLite 存 FTS5（BM25）+ 向量表；查询时先 BM25、再向量、再 0.7/0.3 混合，可选 Rerank。  
- **案例**：查询「qwen-max 模型升级」→ 混合分数 **0.675**，加 Rerank 后 Top1 **0.779**；单次搜索约 **6（仅向量）或 141（+ Rerank）tokens**。

### 2.5 端到端案例：一次 Builtin+Rerank 搜索发生了什么？

假设用户问：**「qwen-max 模型升级」**，且配置了 Builtin + Rerank。下面按时间顺序走一遍（数字对应真实测试）。

1. **查询进来**  
   OpenClaw 调用 `MemoryIndexManager.search("qwen-max 模型升级", { maxResults: 6 })`。

2. **BM25**  
   - 从查询里抽出 token（如 `qwen`, `max`），在 FTS 表里 `MATCH`。  
   - 库里只有 1 个 chunk，若命中，得到 `rank`，转成 `textScore`（例如 0.3）。

3. **向量**  
   - 用「qwen-max 模型升级」调百炼 text-embedding-v4，得到 1024 维向量（**消耗约 8 token**，测试数据）。  
   - 在向量表里算余弦相似度，同一 chunk 得到 `vectorScore`（例如 0.8）。

4. **合并**  
   - 该 chunk 的 `score = 0.7 * 0.8 + 0.3 * 0.3 = 0.65`（与实测 0.675 同量级）。  
   - 过滤 `minScore` 后只剩这一条，进入 Rerank。

5. **Rerank**  
   - 请求体：`query: "qwen-max 模型升级"`，`documents: [ "…将默认模型从 qwen-plus 升级为 qwen-max…" ]`。  
   - 百炼 gte-rerank 返回该句的 `relevance_score: 0.779`（**消耗约 138 token**，测试数据）。  
   - 最终返回给上层的这条记忆，score 就是 **0.779**。

6. **结果**  
   - 用户看到的首条记忆片段就是「将默认模型从 qwen-plus 升级为 qwen-max…」，且分数 0.779。  
   - 整次搜索约 **8 + 138 ≈ 146 token**，和文档里「单次约 141 token」一致（不同查询 token 略有波动）。

这样走一遍，就能把「BM25 → 向量 → 合并 → Rerank」和真实数字对上号。

---

## 三、QMD 后端的三种模式（search / vsearch / query）

QMD 是**独立 CLI 工具**，OpenClaw 通过配置 `memory.backend: "qmd"` 调用它执行搜索，并把结果转成和 Builtin 相同的结果格式。  
这里说的是 **QMD 远程模式**（用百炼 text-embedding-v4 + gte-rerank，**不用本地大模型**）。

### 3.1 三种模式分别做什么？

| 模式 | 命令 | 实际做的事 | 是否用 Embedding | 是否用 Rerank |
|------|------|------------|------------------|----------------|
| **search** | `qmd search "…"` | 纯 BM25 关键词 | 否 | 否 |
| **vsearch** | `qmd vsearch "…"` | 查询扩展 + 多路向量搜索 | 是 | 否 |
| **query** | `qmd query "…"` | 查询扩展 + BM25 + 向量 + 合并去重 + Rerank | 是 | 是 |

下面用同一句查询 **「qwen-max 模型」** 和测试数据说明。

### 3.2 search 模式：纯 BM25

- **流程**：用户输入 → 直接作为 FTS 查询，在 QMD 的 SQLite FTS 表上做 `MATCH`，按 bm25 排序输出。  
- **特点**：不调用任何远程模型，**Token 消耗为 0**，延迟主要来自 SQLite。  
- **案例**：测试里 `qmd search "qwen-max 模型"` 约 **0.5s**，但对中文分词支持差，**常出现 0 条结果**（例如「qwen-max 模型升级」无结果）。适合英文或简单关键词。

### 3.3 vsearch 模式：查询扩展 + 向量

- **流程**：  
  1. **查询扩展**（远程模式下为启发式）：把用户查询变成多句「变体」，例如保留原句 + 加一句 "Information about qwen-max 模型"，类型标记为 `vec` / `hyde` 等。  
  2. 对每一个变体调用 **text-embedding-v4** 得到向量，在 QMD 的向量索引里做相似度搜索。  
  3. 多路结果去重、合并、按分数排序后返回。  
- **特点**：用多句查询提高召回，但**不做 Rerank**，所以排序完全依赖向量相似度。  
- **案例**：同一查询「qwen-max 模型」在 vsearch 下约 **1.0s**，Score **0.57**；5 个查询平均 vsearch 约 1.0s，Score 在 0.35~0.57。  
- **Token**：主要是多句查询的 Embedding，约 **~6 token/次**（和 Builtin 单次 query embed 同量级）。

### 3.4 query 模式：完整管线（BM25 + 向量 + Rerank）

- **流程**：  
  1. **查询扩展**（同上，启发式多句）。  
  2. **多路搜索**：对「lex」类做 BM25，对「vec」/「hyde」类做向量搜索。  
  3. **合并去重**：按文档/块 ID 合并，避免同一段出现多次。  
  4. **Rerank**：把「用户原始查询 + 候选 snippet 列表」发给 **gte-rerank**，按返回的 relevance_score 重排，取 topN。  
- **特点**：既有多路召回，又有精排，所以 **Top1 质量最高**。  
- **案例**：同一查询「qwen-max 模型」在 query 下约 **1.1s**，Score **0.91**；5 个查询的 Score 在 **0.76~0.91**。  
- **Token**：Embedding（多句）约 ~6 + Rerank 约 ~135 ≈ **141 token/次**，和 Builtin+Rerank 同量级。

### 3.5 用测试数据对比三种模式（同一查询）

以「qwen-max 模型」为例（测试环境：1 个 md 文件，1 个 chunk）：

| 模式 | 耗时 | Score | Token |
|------|------|-------|--------|
| search | ~0.5s | 常为 0（无命中） | 0 |
| vsearch | ~1.0s | 0.57 | ~6 |
| query | ~1.1s | **0.91** | ~141 |

可以看到：**query 模式用多约 135 token 的 Rerank，把 0.57 提到 0.91**，对首条质量提升非常明显。

### 3.6 QMD 远程模式下的「实现细节」

- **谁在算向量 / 谁在 Rerank？**  
  在 `QMD_LLM_PROVIDER=remote` 时，QMD 内部用的是 **DashScopeRemoteLLM**：  
  - `embed` / `embedBatch` → 请求百炼 **text-embedding-v4**（OpenAI 兼容）；  
  - `rerank` → 请求百炼 **gte-rerank** 原生接口。  
  所以和 Builtin 一样，**没有任何本地大模型**，Token 都花在百炼 API 上。

- **OpenClaw 如何调用 QMD？**  
  OpenClaw 的 `QmdMemoryManager.search()` 会根据 `memory.qmd.searchMode`（如 `query`）拼出命令行参数，例如：  
  `qmd query "用户输入" --json -n 6 -c memory-dir …`，  
  然后 `spawn(qmd, args, { env: this.env })` 执行子进程；`this.env` 里已经带上 `QMD_LLM_PROVIDER=remote` 和各类 `QMD_*` 变量，所以子进程里 QMD 走的就是远程 API。  
  解析 stdout 的 JSON，转成 `MemorySearchResult[]`（path、snippet、score 等），和 Builtin 的返回格式一致，上层无感。

---

## 四、几种机制的并排对比（实现 + 数据）

下面用「实现要点 + 同一批测试数据」并排对比，方便一眼看懂差异。

### 4.1 管线对比（谁先谁后）

- **Builtin（无 Rerank）**  
  查询 → 1 次 Embedding → BM25 检索 + 向量检索 → 0.7/0.3 合并 → 按 score 截断返回。  

- **Builtin + Rerank**  
  在上一行基础上，对合并后的前若干条再调 gte-rerank，按 relevance_score 重排后返回。  

- **QMD search**  
  查询 → 直接 FTS BM25 → 返回，无 Embedding、无 Rerank。  

- **QMD vsearch**  
  查询 → 启发式扩展成多句 → 每句 Embedding → 多路向量搜索 → 合并去重排序 → 返回。  

- **QMD query**  
  查询 → 启发式扩展 → BM25 + 多路向量 → 合并去重 → **Rerank** → 返回。

### 4.2 用 5 个测试查询的统计结果（摘要）

| 机制 | 平均耗时 | 平均/最高 Score | Embed Token/次 | Rerank Token/次 | 总 Token/次 |
|------|----------|-----------------|----------------|-----------------|-------------|
| Builtin（仅向量） | ~400ms | 0.36~0.68 | ~6 | 0 | **~6** |
| Builtin + Rerank | ~700ms | Top1≈0.78 | ~6 | ~135 | **~141** |
| QMD search | ~550ms | 常 0（中文差） | 0 | 0 | **0** |
| QMD vsearch | ~1.0s | 0.35~0.57 | ~6 | 0 | **~6** |
| QMD query | ~1.1s | **0.76~0.91** | ~6 | ~135 | **~141** |

（上面 Embed/Rerank 的 token 数是根据测试报告和接口用法估算的，和文档里「Token 消耗对比」一致。）

### 4.3 为什么 Rerank 能明显提高「首条」质量？

- **合并/向量**只依赖：  
  - BM25 的「词频/逆文档频」；  
  - 向量的「语义相似度」。  
  它们都不会显式地判断「这句话是不是在直接回答这个问题」。  
- **Rerank 模型**（gte-rerank）的输入是「一个问题 + 多条候选句子」，输出是每条候选对**该问题**的 relevance_score，相当于在做「阅读理解：哪一句最贴题？」。  
  所以能把「将默认模型从 qwen-plus 升级为 qwen-max…」这种直接相关句排到第一，而把「支持渠道：飞书、Discord…」这种弱相关句排后，**Top1 从 0.57 提到 0.91** 就是这样来的。

---

## 五、总结：一眼看懂该选谁

- **只要「能搜到」且省 Token**：Builtin 不开 Rerank（~6 token/次）或 QMD vsearch（~6 token/次）；QMD search 对中文差，一般不选。  
- **要「首条尽量准」**：Builtin + Rerank 或 QMD query（~141 token/次），首条分数可到 0.76~0.91。  
- **要零 Token、能接受中文差**：QMD search（0 token，约 0.5s）。  
- **实现上**：Builtin 全在 OpenClaw 进程内（SQLite + 百炼 API）；QMD 是子进程调 CLI，通过环境变量走百炼远程 API，**两种都没有本地大模型**，所有「智能」都来自百炼的 text-embedding-v4 和 gte-rerank。

把上述实现原理和测试数据对应起来，就可以在不熟悉搜索引擎和向量模型的前提下，一眼理解每种 MEMORY 机制在做什么、为什么会有这样的质量和 Token 消耗。
