# Memory 切换与验证命令速查

> 用于确认当前记忆后端、切换 builtin/qmd、以及验证回答是否按所选方式执行。  
> **若执行 `openclaw config set` 或 `openclaw memory status` 报错「Config invalid」**，请改用本文中的「不依赖 OpenClaw CLI」的切换与验证方式。

---

## 一、查看当前使用的后端（验证「真的用到了」）

### 1. 不依赖 OpenClaw CLI（推荐，配置校验失败时必用）

直接读配置文件中的 `memory.backend`，不依赖 OpenClaw 进程与校验：

```bash
# 用 jq（无 jq 时用下面 Python 一行）
jq -r '.memory.backend // "builtin"' ~/.openclaw/openclaw.json
```

或：

```bash
python3 -c "import json; c=json.load(open('$HOME/.openclaw/openclaw.json')); print(c.get('memory',{}).get('backend','builtin'))"
```

- 输出 `builtin` 或 `qmd` 表示**配置里**当前选择的后端；未配置时默认为 `builtin`。
- **注意**：这是「配置中的值」。若选的是 qmd 但 QMD 启动失败，实际运行会 fallback 到 builtin，此时需看网关日志或运行中的 status（见下）。

### 2. 人类可读（需配置通过校验）

```bash
openclaw memory status
```

若报错 **Config invalid**（例如 `Unrecognized key: "rerank"`），说明当前配置含未识别字段，请用上一种方式查看配置中的 backend。

看输出中的 **Backend** 行（需 OpenClaw 版本包含 Backend 输出）：

- `Backend: builtin` → 当前为 OpenClaw 原生
- `Backend: qmd` → 当前为 QMD 侧车

若没有 Backend 行，可看 **Provider**：`openai`（或你配的）= builtin，`qmd` = QMD。

### 3. 机器可读（需配置通过校验）

```bash
openclaw memory status --json | jq -r '.[0].status.backend'
```

输出为 `builtin` 或 `qmd`。

### 4. 指定 Agent

```bash
openclaw memory status --agent main
openclaw memory status --json --agent main | jq '.[0].status.backend'
```

---

## 二、切换后端

**若执行 `openclaw config set` 报错「Config invalid」或「Unrecognized key」**，请改用**方式 B（编辑配置）或方式 C（脚本）**，二者不依赖 OpenClaw 配置校验。

### 方式 A：config set + 重启（仅当配置完全合法时可用）

```bash
# 切换到 Builtin
openclaw config set memory.backend builtin
openclaw gateway restart

# 切换到 QMD
openclaw config set memory.backend qmd
openclaw gateway restart
```

**必须重启网关**，backend 在进程启动时读取。若此处报 Config invalid，请用方式 B 或 C。

### 方式 B：编辑配置文件（推荐，校验失败时必用）

编辑 `~/.openclaw/openclaw.json`，设置：

```json
{
  "memory": {
    "backend": "builtin"
  }
}
```

或 `"backend": "qmd"`，保存后执行：

```bash
openclaw gateway restart
```

**验证配置中的 backend**（不依赖 OpenClaw CLI）：

```bash
jq -r '.memory.backend // "builtin"' ~/.openclaw/openclaw.json
```

### 方式 C：使用脚本（推荐，校验失败时必用）

从项目根或使用脚本绝对路径执行，脚本直接改 JSON，不依赖 OpenClaw：

```bash
# 仅改配置，不重启
bash doc/scripts/memory-switch.sh builtin
bash doc/scripts/memory-switch.sh qmd

# 改配置并重启 gateway
bash doc/scripts/memory-switch.sh builtin --restart
bash doc/scripts/memory-switch.sh qmd --restart
```

验证：`jq -r '.memory.backend // "builtin"' ~/.openclaw/openclaw.json`

---

## 三、验证「回答按所选方式执行」的完整流程

```bash
# 1. 记录当前后端
openclaw memory status
openclaw memory status --json | jq '.[0].status.backend' > /tmp/backend_before.txt

# 2. 切换到 Builtin
openclaw config set memory.backend builtin
openclaw gateway restart
sleep 3

# 3. 确认已是 builtin
openclaw memory status
openclaw memory status --json | jq -r '.[0].status.backend'
# 应输出: builtin

# 4. 用 CLI 搜一条记忆（便于和对话对比）
openclaw memory search "qwen-max 模型" 2>/dev/null || true

# 5. 再切换到 QMD
openclaw config set memory.backend qmd
openclaw gateway restart
sleep 3

# 6. 确认已是 qmd（若 QMD 可用）
openclaw memory status
openclaw memory status --json | jq -r '.[0].status.backend'
# 应输出: qmd
# 若出现 Fallback 行，说明 QMD 失败，实际在用 builtin

# 7. 再次用 CLI 搜同一条（可选）
openclaw memory search "qwen-max 模型" 2>/dev/null || true
```

对话里问「依赖记忆」的问题（如「我配置的默认模型是什么？」），对比两种 backend 下 status 与回答是否一致、是否都来自记忆，即可确认回答是按所选方式执行的。

---

## 四、常见问题

| 现象 | 可能原因 | 建议 |
|------|----------|------|
| 配置改成 qmd 但 status 仍是 builtin | 未重启 gateway，或 QMD 初始化失败触发了 fallback | 执行 `openclaw gateway restart`；看 status 的 Fallback 行或网关日志 |
| status 里没有 Backend 行 | 使用的 OpenClaw 版本较旧 | 用 `openclaw memory status --json \| jq '.[0].status.backend'` 查看；或升级到含 Backend 输出的版本 |
| 切换后回答好像没变 | 两种后端若索引同一批文件，检索结果可能相似 | 正常；重点看 status 的 backend 是否随配置切换，以及日志是否有 qmd fallback |

---

## 五、相关文档

- 默认机制与验证说明：`doc/sum/MEMORY默认机制与切换验证.md`
- 实现原理与案例：`doc/sum/MEMORY机制实现原理.md`
- 切换脚本：`doc/scripts/memory-switch.sh`
