# OpenClaw 默认记忆机制与切换验证

> 说明：默认是哪种、当前用的是哪种、如何验证、如何切换、如何确认回答按所选方式执行  
> 更新日期: 2026-02-16

---

## 一、默认记忆机制原理

### 1.1 代码里的「默认」是什么？

在 OpenClaw 源码中，Memory 后端的默认值在 **`openclaw-src/src/memory/backend-config.ts`** 中定义：

```ts
const DEFAULT_BACKEND: MemoryBackend = "builtin";
// ...
const backend = params.cfg.memory?.backend ?? DEFAULT_BACKEND;
```

含义：

- 若配置里**没有**写 `memory.backend`，或 `memory` 整段都没有，则使用 **`builtin`**。
- 只有显式配置 `memory.backend: "qmd"` 时，才会走 QMD 后端。

因此：**默认记忆机制 = Builtin 后端**（OpenClaw 原生 SQLite + BM25 + 向量 + 可选 Rerank）。

### 1.2 默认机制（Builtin）在做什么？

简要流程：

1. **索引**：把 `MEMORY.md` 和 `memory/*.md`（及可选会话转录）按块切分，每块调用百炼 **text-embedding-v4** 得到向量，写入 SQLite；同时原文进入 FTS5 做 BM25 关键词索引。
2. **搜索**：用户查询时  
   - 用 BM25 在 FTS5 里做关键词检索；  
   - 用查询句的向量（同上 embedding 接口）在向量表里做相似度检索；  
   - 按配置权重（默认 0.7 向量 + 0.3 关键词）合并排序；  
   - 若开启 `query.rerank`，再对前若干条调百炼 **gte-rerank** 精排。
3. **谁在用**：对话时，Agent 的 **memory_search** 工具会调用上述搜索，把得到的片段注入上下文，模型再基于这些内容回答。

所以「默认」= 始终用 **Builtin** 这一套，除非你在配置里改成 `qmd`。

### 1.3 当前配置 vs 当前实际使用的后端

- **当前默认（代码）**：`builtin`（见 1.1）。
- **当前配置（你机器上的 `~/.openclaw/openclaw.json`）**：若存在 `memory.backend`，以该值为准；若不存在，则为默认 `builtin`。
- **当前实际使用的后端**：由「配置 + 运行时」共同决定：
  - `memory.backend === "builtin"` → 实际使用 **Builtin**。
  - `memory.backend === "qmd"` → 尝试使用 **QMD**；若 QMD 初始化或搜索失败，会 **fallback 到 Builtin**（并打日志 `qmd memory failed; switching to builtin`）。

因此：**「目前用的是哪种」= 看运行时 status 或日志，而不是只看配置文件**（因为可能有 fallback）。

---

## 二、如何确认「真的用到了」所选方式

### 2.1 方法一：CLI 查看 Backend（推荐）

执行：

```bash
openclaw memory status
```

输出中会有一行 **Backend**（若使用含该改动的 OpenClaw 版本）：

- `Backend: builtin` → 当前该 Agent 使用的是 **OpenClaw 原生 Builtin**。
- `Backend: qmd` → 当前该 Agent 使用的是 **QMD**。

同时可看 **Provider**：

- Builtin 时一般为 `openai`（或你配置的 embedding provider）。
- QMD 时为 `qmd`。

**JSON 方式（便于脚本）：**

```bash
openclaw memory status --json
```

用 `jq` 取后端：

```bash
openclaw memory status --json | jq -r '.[0].status.backend'
```

输出为 `builtin` 或 `qmd`。

**当 `openclaw memory status` 或 `openclaw config set` 报错「Config invalid」时**（例如提示 `Unrecognized key: "rerank"`）：说明当前安装的 OpenClaw 的配置 schema 不包含你配置里的某些字段，CLI 会拒绝加载配置。此时请用「不依赖 OpenClaw CLI」的方式查看或切换：

- **查看配置中的 backend**：  
  `jq -r '.memory.backend // "builtin"' ~/.openclaw/openclaw.json`  
  输出即配置文件里当前选择的后端（未配置时等价于 `builtin`）。
- **切换**：用脚本 `bash doc/scripts/memory-switch.sh builtin|qmd`，或直接编辑 `~/.openclaw/openclaw.json` 的 `memory.backend`，然后 `openclaw gateway restart`。  
  详见：`doc/scripts/memory-切换与验证命令.md`。

### 2.2 方法二：对话时看 memory_search 工具返回

当用户问题触发「记忆搜索」时，Agent 会调用 **memory_search** 工具。工具返回的 JSON 里包含当前这次搜索使用的后端信息（由 `manager.status()` 提供）：

- `provider`: 对 Builtin 为 embedding 的 provider（如 `openai`），对 QMD 为 `qmd`。
- 若为 QMD 且发生过 fallback，还可能带 `fallback` 等字段。

因此：**若能在日志或调试中看到某次 memory_search 的返回**，其中的 `provider` / 后端相关字段即表示「这次回答用的是哪种机制」。

### 2.3 方法三：看 Gateway 日志

- 使用 **QMD** 且某次搜索失败时，会打出一行类似：  
  `qmd memory failed; switching to builtin index: ...`  
  表示该次已回退到 Builtin。
- 若配置为 QMD 且从未出现此日志，且 status 为 `qmd`，则可认为回答是基于 **QMD** 的。

---

## 三、切换不同模式并验证「回答按选择的方式」执行

### 3.1 切换命令（概要）

- 切到 **Builtin**：  
  `openclaw config set memory.backend builtin`  
  然后重启网关：`openclaw gateway restart`（若使用 gateway）。
- 切到 **QMD**：  
  `openclaw config set memory.backend qmd`  
  同样需要 **重启网关** 后新配置才生效（backend 在进程启动时解析）。

或直接编辑 `~/.openclaw/openclaw.json`，设置 `memory.backend` 为 `builtin` 或 `qmd`，再重启。

### 3.2 验证步骤（建议流程）

1. **切换前记录**  
   - `openclaw memory status` 记下当前 **Backend** 和 **Provider**。  
   - 可选：`openclaw memory status --json | jq '.[0].status'` 保存一份。

2. **切换到 Builtin**  
   - `openclaw config set memory.backend builtin`  
   - `openclaw gateway restart`（如有）  
   - 再次执行 `openclaw memory status`，确认 **Backend: builtin**，**Provider** 为 openai（或你配置的 embedding）。

3. **用「依赖记忆」的问题测一次**  
   - 例如问：「我之前配置的默认模型是什么？」或「记忆里关于 qwen-max 的配置有哪些？」  
   - 若记忆中有相关内容，应返回基于 **Builtin 索引** 的检索结果；  
   - 验证方式：同一问题下，`openclaw memory search "qwen-max 模型"`（CLI 搜索）得到的片段，应与对话中模型引用的内容一致（同一套索引）。

4. **切换到 QMD**  
   - `openclaw config set memory.backend qmd`  
   - 确保 QMD 已按文档配置（含 `QMD_LLM_PROVIDER=remote` 等 env），且 `qmd` 可执行。  
   - `openclaw gateway restart`。

5. **再次看 status**  
   - `openclaw memory status` → 应看到 **Backend: qmd**，**Provider: qmd**。  
   - 若出现 fallback，会看到 **Fallback** 行或日志中的 `qmd memory failed; switching to builtin`。

6. **再问同一类「依赖记忆」的问题**  
   - 若 status 确认为 qmd 且无 fallback，则此次回答应基于 **QMD 的索引与搜索管线**（例如 query 模式下的 BM25 + 向量 + rerank）。  
   - 可与 Builtin 下的回答对比：若索引内容一致，两种后端在「找得到」的前提下都应能答；差异主要体现在排序、片段边界等，可通过 memory search 的返回内容对比。

7. **结论**  
   - 若在 Builtin 时 status 为 builtin、在 QMD 时 status 为 qmd 且无 fallback，且对话中能明显引用到记忆内容，即可认为 **OpenClaw 的回答是按所选后端执行的**。

### 3.3 简单案例说明

- **配置**：`memory.backend = "builtin"`，且 `agents.defaults.memorySearch` 使用 text-embedding-v4 + rerank。  
- **操作**：用户问「我用的 embedding 模型是哪个？」  
- **预期**：Agent 调用 memory_search，Backend 为 builtin，检索到含「text-embedding-v4」的片段，模型回答会提到该模型。  
- **验证**：`openclaw memory status` 为 `Backend: builtin`；若把 backend 改为 `qmd` 并重启，再问同一问题，status 应为 `Backend: qmd`，且若 QMD 索引了相同记忆，回答仍应能提到同一信息，但检索路径为 QMD 管线。

---

## 四、原理小结（便于一眼看懂）

| 项目 | 说明 |
|------|------|
| **默认机制** | **Builtin**（代码中 `DEFAULT_BACKEND = "builtin"`）。 |
| **默认在做什么** | SQLite 存 FTS5 + 向量；搜索时 BM25 + 向量混合，可选 gte-rerank 精排；全部用百炼远程 API，无本地大模型。 |
| **当前用的是哪种** | 由 `memory.backend` 决定；若为 `qmd` 且失败会 fallback 到 builtin，因此以 **运行时 status** 为准。 |
| **怎么测试真的用到了** | ① `openclaw memory status` 看 **Backend**；② 看 memory_search 返回里的 provider/后端；③ 看网关日志是否有 qmd fallback。 |
| **切换后如何验证回答** | 切换后重启 → 再执行 `openclaw memory status` 确认 Backend → 用依赖记忆的问题提问 → 确认回答内容与当前后端索引一致（必要时用 `openclaw memory search "关键词"` 对比）。 |

---

## 五、相关文档与脚本

- **实现原理与案例**：`doc/sum/MEMORY机制实现原理.md`
- **机制总结与配置示例**：`doc/sum/MEMORY机制总结.md`
- **切换与验证命令速查**：`doc/scripts/memory-切换与验证命令.md`（见下）
- **脚本**：`doc/scripts/memory-switch.sh` 可用于切换 backend 并可选重启。
