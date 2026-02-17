# 飞书发邮件到 Gmail 故障修复

> 日期：2026-02-17  
> 状态：**已修复**

---

## 一、问题描述

用户通过飞书向 OpenClaw 发送：

> 「请帮我整理AI圈最热的十个新问题发给我的google邮箱，邮箱：lifeng.zhan90@gmail.com」

**预期**：Agent 整理内容后，把邮件发到该 Gmail。  
**实际**：没有收到该邮件。

---

## 二、原因分析

OpenClaw Agent 的 **message** 工具只能把内容发回**已配置的聊天渠道**（飞书、Telegram、Slack 等），**没有「发邮件到指定 Gmail」的能力**。因此当用户要求「发到我的 Google 邮箱」时，Agent 无法执行发信，只能回复到飞书，邮件不会发出。

---

## 三、修复方案

### 3.1 新增 `gmail_send` Agent 工具

在 OpenClaw 中新增工具 **`gmail_send`**，供 Agent 调用以发送纯文本邮件到任意 Gmail/Google 邮箱：

- **参数**：`to`（收件人）、`subject`（主题）、`body`（正文，支持 `\n` 换行）
- **依赖**：本机已安装并授权 **gog**（gogcli），且配置中设置了 **`hooks.gmail.account`**（用作 Gmail API 发件账号）
- **实现**：内部调用 `gog gmail send --to ... --subject ... --body-file <临时文件>`，使用 `hooks.gmail.account` 作为 `GOG_ACCOUNT` 环境变量

代码位置：

- 工具实现：`openclaw-src/src/agents/tools/gmail-send-tool.ts`
- 注册：`openclaw-src/src/agents/openclaw-tools.ts`（`createGmailSendTool`）
- System prompt 摘要：`openclaw-src/src/agents/system-prompt.ts`（`gmail_send` 的 coreToolSummaries 与 toolOrder）

### 3.2 配置要求

1. **gog 已安装并完成 Gmail 授权**（与 [Gmail 配置为 OpenClaw 专属 Channel](./Gmail配置为OpenClaw专属Channel.md) 一致）  
   - `gog auth credentials <凭据 JSON>`  
   - `gog auth add <你的Gmail>@gmail.com --services gmail`

2. **在 OpenClaw 配置中设置发件账号**（与 Gmail Watch 使用同一账号即可）：
   ```bash
   openclaw config set hooks.gmail.account "lifeng.zhan90@gmail.com"
   ```
   若已运行过 `openclaw webhooks gmail setup --account ...`，该项通常已存在。

3. **重启 Gateway**，使新工具与配置生效：
   ```bash
   openclaw gateway restart
   ```

---

## 四、验证

### 4.1 CLI 验证（推荐先做）

在配置好 `hooks.gmail.account` 并重启 Gateway 后，本地执行：

```bash
openclaw agent --agent main --local --message "请使用 gmail_send 工具发一封邮件到 lifeng.zhan90@gmail.com：主题写「OpenClaw 飞书发信验证」，正文写「这是一封由 OpenClaw Agent 通过 gmail_send 工具发送的验证邮件。」"
```

**预期**：Agent 调用 `gmail_send`，返回成功信息（含 `message_id`），并在 Gmail 收件箱收到该邮件。

### 4.2 飞书端验证

在飞书中对 OpenClaw 机器人发送例如：

- 「请整理 AI 圈最热的十个新问题，用邮件发到 lifeng.zhan90@gmail.com」

**预期**：Agent 会先通过 `web_search` 等整理内容，再调用 `gmail_send` 将结果发到指定邮箱；飞书内会收到「已发送到你的 Gmail」类回复，Gmail 收件箱收到对应邮件。

若飞书侧提示「工具 `gmail_send` 当前不可用 (未注册或未启用)」或只回复文字、未发邮件，按下面三项排查：

1. **Gateway 必须重启**  
   飞书请求由 **Gateway 进程** 处理；命令行 `openclaw agent --local` 是当前进程、已含新代码。若未执行过 `openclaw gateway restart`，Gateway 仍是旧版本，不会加载 `gmail_send`。  
   → 执行：`openclaw gateway restart`，再在飞书里重试。

2. **工具策略已包含 gmail_send**  
   若 agent 或渠道启用了工具 allowlist（如 `tools.allow: ["group:messaging"]` / `["group:openclaw"]`），`gmail_send` 现已加入这两个组，重启后会被一并允许。若仍不可用，检查 `agents.list[].tools.allow` 是否包含 `gmail_send` 或上述 group。

3. **会话历史导致模型误判「未注册」**  
   若某次运行中曾出现「Tool gmail_send not found」（例如用过旧版本或未重启 Gateway），该会话历史会让模型在后续轮次中不再尝试调用 `gmail_send`，转而虚构「已用底层 API 发送」等回复（实际未发信）。  
   → **处理**：对该会话做 **重置**（在对应渠道使用 `/reset` 或 `/new`），或使用 **新会话** 再试。命令行验证时可用全新 `--session-id` 或删除/清空该 agent 的 session 文件后再跑一次。

4. **模型是否稳定调用工具**  
   参考 [飞书浏览器工具调用故障修复](./飞书浏览器工具调用故障修复.md) 中关于模型 tool calling 的说明。

---

## 五、配置与故障排查速查

| 项目 | 说明 |
|------|------|
| **工具名** | `gmail_send` |
| **配置** | `hooks.gmail.account` 必须为已用 gog 授权的 Gmail 地址 |
| **依赖** | 本机已安装 `gog`，且已完成 `gog auth add <email> --services gmail` |
| **未配置时** | 工具返回错误：`Gmail send not configured. Set hooks.gmail.account in openclaw config` |
| **gog 未安装** | 工具返回：提示安装 `brew install steipete/tap/gogcli` 并完成 auth |
| **飞书侧提示「gmail_send 未注册或未启用」** | 多为 Gateway 未重启（仍跑旧代码）；或该 agent 的 tools.allow 未包含 gmail_send；或**会话历史**里曾出现「Tool gmail_send not found」导致模型不再调用该工具。已把 gmail_send 加入 `group:messaging` 与 `group:openclaw`；若仍不调用，对该会话做 `/reset` 或换新会话再试。 |

---

## 六、Dashboard 使用说明

`openclaw dashboard` 会输出 Dashboard URL 并尝试在浏览器打开。若「不成功」可能表现为：

- **浏览器未自动打开**：可手动复制终端里打印的 URL 到浏览器。
- **页面打不开或一直加载**：Dashboard 依赖 **Gateway 进程** 提供后端；若未启动 Gateway，页面无法连接。  
  → 先执行 `openclaw gateway` 或 `openclaw gateway start`，再访问 Dashboard URL。
- **页面提示「Control UI assets not found」**：前端资源未构建。推荐直接使用 **基于 openclaw-src 的打包安装**，这样 CLI、Gateway 和 Control UI 均来自同一构建，避免路径不一致：
  1. 在项目根目录下执行：`cd openclaw-src && pnpm pack`（会先执行 prepack：build + ui:build，再生成 `openclaw-<version>.tgz`）。
  2. 全局安装：`pnpm add -g ./openclaw-2026.2.12.tgz`（版本号以 package.json 为准）。
  3. 之后使用 `openclaw`、`openclaw gateway`、`openclaw dashboard` 均指向此次安装，Dashboard 的 Control UI 资源已包含在包内（`dist/control-ui`）。**若之前已有 Gateway 在运行，需执行 `openclaw gateway restart`**，新进程才会从当前安装目录解析到 `dist/control-ui`，否则仍会返回 503「Control UI assets not found」。
  若仅想临时构建 UI 而不重装：在**项目源码目录**执行 `pnpm ui:build`，并让 Gateway 从该目录启动，或配置 `gateway.controlUi.root` 指向 `openclaw-src/dist/control-ui`。

---

## 七、相关文档

- [Gmail 配置为 OpenClaw 专属 Channel](./Gmail配置为OpenClaw专属Channel.md) — Gmail 收信 + 发信环境（gog、OAuth、hooks.gmail）
- [飞书浏览器工具调用故障修复](./飞书浏览器工具调用故障修复.md) — 飞书侧模型 tool calling 与浏览器工具问题
