# OpenClaw 集成 Gemini CLI 与 Cursor CLI 验证总结

> 版本：2026-02  
> 内容：Gemini CLI / Cursor CLI 的 Tool + Skill 接入说明与 openclaw 命令验证方式

---

## 1. 集成概览

| 项目 | 工具名 | Skill | 参考文档 |
|------|--------|--------|----------|
| **Gemini CLI** | `gemini_cli` | `skills/gemini` | `doc/ai-code-cli/gemini-cli.md` |
| **Cursor CLI** | `cursor_cli` | `skills/cursor-cli` | `doc/ai-code-cli/cursor-cli.md` |

- **Tool**：在 OpenClaw 中由 Agent 调用的能力（`createOpenClawTools` 注册）。
- **Skill**：给模型看的说明与安装/环境要求（`openclaw-src/skills/<name>/SKILL.md`）。

---

## 2. 实现位置

- **Tools**
  - `openclaw-src/src/agents/tools/gemini-cli-tool.ts` — 调用本地 `gemini "prompt"`（可选 `--model`、`--output-format json`）。
  - `openclaw-src/src/agents/tools/cursor-cli-tool.ts` — 调用 `cursor-agent --print --trust --mode ask --output-format text "prompt"`（可选 `--model`）。见下文根因说明为何必须带 `--trust` 与关闭 stdin。
- **注册**
  - `openclaw-src/src/agents/openclaw-tools.ts` 中已加入 `createGeminiCliTool()` 与 `createCursorCliTool()`。
- **Skills**
  - `openclaw-src/skills/gemini/SKILL.md` — 已补充 OpenClaw 工具 `gemini_cli` 说明。
  - `openclaw-src/skills/cursor-cli/SKILL.md` — 新建，说明 `cursor_cli` 与 Cursor CLI 用法。

---

## 3. 前置条件

- **Gemini CLI**：本机已安装 `gemini`（如 `brew install gemini-cli`），并按需完成一次交互登录。
- **Cursor CLI**：本机已安装 Cursor CLI（如 `curl https://cursor.com/install -fsS | bash`），并具备 Cursor 订阅/额度。

---

## 4. 验证方式（openclaw 命令）

### 4.1 一键脚本（推荐）

从仓库根目录执行（会先构建 openclaw-src，再检查工具是否注册，可选用 gemini 跑一次 agent）：

```bash
bash doc/sum/scripts/verify-ai-code-cli-tools.sh
```

- 若未指定 `OPENCLAW_SRC`，默认使用 `./openclaw-src`。
- 脚本会：
  1. 检查/构建 `openclaw-src`。
  2. 用 Node 加载 `createOpenClawTools`，确认 `gemini_cli` 与 `cursor_cli` 在工具列表中。
  3. 若本机有 `gemini`，则用 `openclaw agent` 发一条让 Agent 使用 `gemini_cli` 的消息做可选 E2E 验证。

### 4.2 手动验证工具已注册（单元测试）

在 openclaw-src 下执行：

```bash
cd openclaw-src
pnpm test -- src/agents/openclaw-tools.ai-code-cli.test.ts --run
```

通过即表示 `gemini_cli` 与 `cursor_cli` 已出现在默认工具列表中。

### 4.3 通过 Agent 调用工具

- **Gemini CLI**（需已安装 `gemini`）：
  ```bash
  openclaw agent --agent main --local --message "请用 gemini_cli 问：1+1 等于几？"
  ```
- **Cursor CLI**（需已安装 `cursor-agent`）：
  ```bash
  openclaw agent --agent main --local --message "请用 cursor_cli 执行：解释什么是 REST API，一句话。"
  ```

若模型选择了对应工具且本机 CLI 可用，应能看到工具返回内容。

---

## 5. 为何 Gemini 可用而 Cursor 不可用（根因与修复）

在「同一台机器、终端里两个 CLI 都能跑」的前提下，若 OpenClaw 里 **gemini_cli 正常、cursor_cli 报错或卡住**，通常由以下两点导致（已在代码中修复，无需用户改配置）：

| 原因 | 说明 | 代码侧处理 |
|------|------|------------|
| **Workspace Trust** | Cursor Agent 在 headless 下会检查工作区是否信任；未信任则直接退出并提示 `Pass --trust`。Gemini CLI 无此机制。 | 工具默认传入 `--trust`，并 `--mode ask` 只读。 |
| **stdin 继承导致卡住** | 子进程若使用 `stdin=inherit`，cursor-agent 会一直不退出；Gemini 无此行为。 | 调用时传入 `input: ""`，使 stdin 走 pipe 并立即 end。 |
| **PATH / .zshrc** | `cursor-agent` 常只在 `~/.zshrc` 注入的 PATH 中（如 `~/.local/bin`）。代码里 source 的是 **`$HOME/.zshrc`**，与项目目录无关。 | 优先用 `resolveCliBinary` 从 PATH + `~/.local/bin` 等解析；解析不到再通过 zsh 执行。 |

**建议验证（不依赖脚本）**：在终端直接执行  
- 会失败（未信任）：`cursor-agent --print "用一句话说什么是 REST"`  
- 会成功：`cursor-agent --print --trust --mode ask --output-format text "用一句话说什么是 REST"`

---

## 6. 常见问题

- **工具列表里没有 gemini_cli / cursor_cli**  
  - 确认使用的是已包含本次改动的 openclaw-src，并执行过 `npm run build`。  
  - 再跑一遍 `doc/sum/scripts/verify-ai-code-cli-tools.sh` 中的“检查工具注册”步骤。

- **gemini_cli 报错 "gemini not found"**  
  - 安装：`brew install gemini-cli`（或 `npm i -g @google/gemini-cli`），并将 `gemini` 加入 PATH。

- **cursor_cli 报错 "cursor-agent not found"**  
  - 安装 Cursor CLI：`curl https://cursor.com/install -fsS | bash`，并按提示确保 `cursor-agent` 在 PATH 中。用法见 `doc/ai-code-cli/cursor-cli/02-usage.md`。

- **Agent 不选工具**  
  - 在提示中明确写出“请使用工具 gemini_cli / cursor_cli”；或检查当前模型是否支持 function calling，以及 gateway/agent 的 tool 策略是否放行该工具。

- **本地已安装 gemini/cursor-agent，但工具报 “not found”**  
  - **zsh 用户**：在 macOS/非 Windows 上，若存在 `/bin/zsh` 且 PATH 中找不到二进制时，会通过 **`zsh -c 'source ~/.zshrc 2>/dev/null; ...'`** 执行，使用 **`$HOME/.zshrc`**（与项目目录无关）。  
  - **非 zsh 或 Windows**：工具会先在 `~/.local/bin`、`/usr/local/bin` 中查找可执行文件，并在子进程 env 中注入这些路径；若仍报错，请确认上述目录下存在对应可执行文件，并执行 `cd openclaw-src && pnpm run build && openclaw gateway restart`。

- **访问 127.0.0.1:18789 提示 “Control UI assets not found”**  
  - 表示 Control UI 静态资源未构建或网关未找到。在 **openclaw-src** 下执行：`pnpm ui:build`（会自动安装 UI 依赖），然后执行 `openclaw gateway restart`。  
  - 若从源码开发，可改用 `pnpm ui:dev` 启动 UI 开发服务器，并确保网关配置指向该开发地址。

---

## 7. 相关文档

- 参考：`doc/ai-code-cli/gemini-cli.md`、`doc/ai-code-cli/cursor-cli.md`
- 配置与 CLI 总览：`doc/sum/OpenClaw配置与CLI与功能总览.md`
