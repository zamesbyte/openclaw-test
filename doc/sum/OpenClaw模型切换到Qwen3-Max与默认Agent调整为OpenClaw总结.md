# OpenClaw 模型切换到 Qwen3-Max 与默认 Agent 调整为 OpenClaw 总结

> 时间：2026-02-26  
> 环境：macOS，本地安装 OpenClaw CLI（2026.2.12）  
> 目标：  
> - 将默认大模型切到 **dashscope/qwen3-max**；  
> - 确保嵌入式 Agent 与网关使用的模型一致；  
> - 将默认 Agent 调整为通用助手 **OpenClaw**，而不是「赏金猎人 (The Hunter)」人格。

---

## 一、前置状态与问题

1. **配置中残留 Gemini 相关字段，导致 config invalid**

   - `~/.openclaw/openclaw.json` 中存在历史遗留字段：
     - `meta.GEMINI_API_KEY`
   - 任何依赖配置校验的命令（例如 `openclaw config get ...`）会提示：

   ```text
   Config invalid
   File: ~/.openclaw/openclaw.json
   Problem:
     - meta: Unrecognized key: "GEMINI_API_KEY"
   ```

2. **默认模型仍为 dashscope 上旧的 Qwen 系列**

   - 配置中的 `agents.defaults.model.primary` 最初为：
     - `dashscope/qwen-max`（或历史上的 `dashscope/qwen-plus`）
   - 需要切换到 **最新的 Qwen3-Max** 模型。

3. **默认 Agent 虽然名为 OpenClaw，但 workspace 指向 Hunter**

   - `openclaw agents list --plain` 初始表现（关键部分）：

   ```text
   - main (default)
     Identity: 🦞 OpenClaw (config)
     Workspace: ~/.openclaw/workspace-shop-hunter

   - shop-hunter
     Identity: 🕵️ 赏金猎人 (The Hunter) (config)
     Workspace: ~/.openclaw/workspace-shop-hunter
   ```

   - 结果：在 Feishu 等渠道直接对话时，默认人格更像 Hunter，而不是通用的 OpenClaw 助手。

---

## 二、清理历史 Gemini 配置（doctor 修复）

**命令：**

```bash
openclaw doctor --fix
```

**预期效果：**

- 自动从 `~/.openclaw/openclaw.json` 里移除未知字段：
  - `meta.GEMINI_API_KEY`
- 再次运行任何 `openclaw config ...` / `openclaw agents list` 时，不再提示 `Config invalid`。

---

## 三、将默认模型切换到 dashscope/qwen3-max

### 3.1 在 DashScope provider 下配置 Qwen3-Max / Qwen-Max / Qwen-Plus

**命令：**

```bash
openclaw config set models.providers.dashscope.models '[
  {"id":"qwen3-max","name":"Qwen3 Max (Aliyun)","reasoning":false,"input":["text"],"cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0},"contextWindow":131072,"maxTokens":8192},
  {"id":"qwen-max","name":"Qwen Max (Aliyun)","reasoning":false,"input":["text"],"cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0},"contextWindow":131072,"maxTokens":8192},
  {"id":"qwen-plus","name":"Qwen Plus (Aliyun)","reasoning":false,"input":["text"],"cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0},"contextWindow":131072,"maxTokens":8192}
]'
```

**目的：**

- 显式在 `models.providers.dashscope.models` 下声明三个可用模型：`qwen3-max`、`qwen-max`、`qwen-plus`；
- 方便后续通过 `agents.defaults.model.primary` 或 `--model dashscope/qwen3-max` 指定。

### 3.2 设置全局默认模型为 Qwen3-Max

**命令：**

```bash
openclaw config set agents.defaults.model.primary "dashscope/qwen3-max"
openclaw config get agents.defaults.model.primary
```

**预期输出：**

```text
dashscope/qwen3-max
```

说明：

- 所有未显式指定模型的 Agent，将默认使用 `dashscope/qwen3-max`。

### 3.3 模型生效的验证（嵌入式 Agent）

**命令：**

```bash
OPENCLAW_THINKING=low \
openclaw agent --local --agent main --json \
  --message "告诉我你的模型"
```

**关键返回：**

- 文本答复示例：

  > 我当前使用的模型是 **Qwen3-Max**（由通义千问提供）。

- `meta.agentMeta` 中包含：

  ```json
  "provider": "dashscope",
  "model": "qwen3-max"
  ```

这说明：

- 实际调用的底层模型已正确切换为 **dashscope/qwen3-max**；
- Agent 在自我描述中也会说明自己是 Qwen3-Max。

---

## 四、将默认 Agent 调整为通用 OpenClaw（修复 Hunter 默认人格问题）

### 4.1 问题根因

- 多 Agent 初始化脚本在创建 Smart Shopper 场景（`shop-hunter` / `shop-skeptic` / `shop-auditor`）时，同时把默认 Agent `main` 的 `workspace` 指向了：

  ```text
  ~/.openclaw/workspace-shop-hunter
  ```

- OpenClaw 的人格/记忆由 workspace 下的 `AGENTS.md`、`SOUL.md`、`IDENTITY.md` 等文件决定：
  - `workspace-shop-hunter` 内的这些文件定义的是「赏金猎人 (The Hunter)」人格；
  - 导致 `main` 虽然名为 OpenClaw，但加载的是 Hunter 的灵魂。

### 4.2 调整默认 Agent 的 workspace

**命令：**

```bash
openclaw config set 'agents.list[0].workspace' '/Users/zhanlifeng/.openclaw/workspace'
openclaw agents list --plain
```

**预期变化（关键行）：**

```text
- main (default)
  Identity: 🦞 OpenClaw (config)
  Workspace: ~/.openclaw/workspace
```

- 其他多 Agent 仍保持原有 workspace：
  - `shop-hunter` → `~/.openclaw/workspace-shop-hunter`
  - `shop-skeptic` → `~/.openclaw/workspace-shop-skeptic`
  - `shop-auditor` → `~/.openclaw/workspace-shop-auditor`

### 4.3 验证默认 Agent 确实挂载通用 workspace

**命令：**

```bash
OPENCLAW_THINKING=low \
openclaw agent --local --agent main --json \
  --message "现在的工作区路径是什么？只回答路径本身"
```

**预期返回：**

- `payloads[0].text`：

  ```text
  /Users/zhanlifeng/.openclaw/workspace
  ```

- `meta.systemPromptReport.workspaceDir`：

  ```text
  /Users/zhanlifeng/.openclaw/workspace
  ```

- `injectedWorkspaceFiles` 列表中的路径，均指向通用 workspace 下的：
  - `AGENTS.md`
  - `SOUL.md`
  - `IDENTITY.md`
  - `USER.md`
  - `HEARTBEAT.md`
  - `BOOTSTRAP.md`

这表明：

- 默认 Agent `main` 现在加载的是 **通用 OpenClaw 工作区**，人格与记忆来自此处定义，而不是 Hunter 专用 workspace。

### 4.4 渠道侧体验验证（Feishu 等）

完成上述配置与验证后：

1. 重启 OpenClaw 网关 / Mac App：

   - macOS App：退出再打开；  
   - CLI 自建 gateway：重启对应的 `openclaw gateway ...` 进程。

2. 在 Feishu 等渠道重新与机器人对话：

   - 默认人格应表现为泛用的 OpenClaw 助手；  
   - 只有在显式路由到 `shop-hunter` / `shop-skeptic` 等 Agent 时，才会呈现对应角色设定。

---

## 五、最终状态与结论

1. **默认模型**  
   - `agents.defaults.model.primary = "dashscope/qwen3-max"`  
   - 实际调用时 `meta.agentMeta.model = "qwen3-max"`，文本回答中也自报为 Qwen3-Max。

2. **默认 Agent 与工作区**  
   - 默认 Agent：`main (default)`，Identity 为 🦞 OpenClaw；  
   - Workspace：`~/.openclaw/workspace`（通用 OpenClaw 工作区）。

3. **多 Agent 场景保留**  
   - `shop-hunter` / `shop-skeptic` / `shop-auditor` 依旧存在并使用各自的 workspace，仅在需要时通过路由或显式指定 Agent id 调用。

整体效果：

- **日常对话**：默认是通用 OpenClaw + Qwen3-Max 模型；  
- **专项场景**：仍可切换到 Hunter / Skeptic / Auditor 等多 Agent 角色，互不干扰。  

