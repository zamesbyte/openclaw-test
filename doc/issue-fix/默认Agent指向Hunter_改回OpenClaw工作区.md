# 默认 Agent 指向 Hunter 改回 OpenClaw 工作区的修复记录

> 时间：2026-02-26  
> 相关配置：`~/.openclaw/openclaw.json`（agents.list / workspace），多 Agent 场景（shop-hunter / shop-skeptic / shop-auditor）

---

## 问题现象

- 在飞书等渠道与 OpenClaw 对话时，默认出现的人格是 **「赏金猎人 (The Hunter)」**，而不是期望的泛用助手 **OpenClaw**。  
- `openclaw agents list` 显示：

```bash
openclaw agents list --plain
```

输出中关键信息为：

- `main (default)` 的 **Identity** 为 `OpenClaw`，但 **Workspace** 却是 `~/.openclaw/workspace-shop-hunter`。  
- `shop-hunter` 这个专用 Agent 也使用同一个 `workspace-shop-hunter` 目录。

这会导致：即便默认 Agent 是 `main`，但由于其工作区是「赏金猎人」专用 workspace，最终实际人格呈现仍偏向 Hunter。

---

## 根因分析

多 Agent 初始化脚本（Smart Shopper 场景）在创建 `shop-hunter` / `shop-skeptic` / `shop-auditor` 三个 Agent 时，同时把：

- 默认 Agent `main` 的 `workspace` 也指向了 **`~/.openclaw/workspace-shop-hunter`**。

而 OpenClaw 的人格、记忆和行为高度依赖所挂载的 workspace 下的：

- `AGENTS.md` / `SOUL.md` / `IDENTITY.md` / `USER.md` 等文件。

因此：

- 虽然 `main` 的 Identity 配置名是 **OpenClaw**；  
- 但它加载的是 **Hunter 专用 workspace**，所以在聊天界面上默认显得像是在和 Hunter 对话。

---

## 修复方案

1. **将默认 Agent `main` 的 workspace 改回通用工作区**

   在终端执行：

   ```bash
   openclaw config set 'agents.list[0].workspace' '/Users/zhanlifeng/.openclaw/workspace'
   openclaw agents list --plain
   ```

   预期输出中的 `main (default)` 行应变为：

   - `Workspace: ~/.openclaw/workspace`
   - Identity 仍为 `🦞 OpenClaw (config)`

2. **重启 Gateway / Mac App 使配置生效**

   - 若通过 macOS OpenClaw App 使用：退出应用再重新打开；  
   - 若使用 CLI 自行跑 gateway：重启对应的 `openclaw gateway ...` 进程。

3. **保留多 Agent 工作区**

   - `shop-hunter` / `shop-skeptic` / `shop-auditor` 继续使用各自的专用 workspace：  
     - `~/.openclaw/workspace-shop-hunter`  
     - `~/.openclaw/workspace-shop-skeptic`  
     - `~/.openclaw/workspace-shop-auditor`
   - 只有默认 Agent `main` 的 workspace 改回通用目录 `~/.openclaw/workspace`。

---

## 修复后验证

1. **验证默认 Agent 与工作区绑定**

   ```bash
   openclaw agents list --plain
   ```

   预期：

   - `main (default)` 的 Workspace 为 `~/.openclaw/workspace`；  
   - `shop-hunter` 仍为 `~/.openclaw/workspace-shop-hunter`。

2. **用嵌入式 Agent 验证工作区与人格**

   ```bash
   OPENCLAW_THINKING=low \
   openclaw agent --local --agent main --json \
     --message "现在的工作区路径是什么？只回答路径本身"
   ```

   返回的 `payloads[0].text` 与 `meta.systemPromptReport.workspaceDir` 均应为：

   ```text
   /Users/zhanlifeng/.openclaw/workspace
   ```

   说明默认 Agent `main` 已挂载到通用 OpenClaw 工作区。

3. **在飞书等渠道体验验证**

   - 重启 gateway / App 后，在飞书中重新与机器人开启会话；  
   - 期望默认人格呈现为 **OpenClaw**（而非「赏金猎人 (The Hunter)」），回答不再绑定 Hunter 专用任务设定。

---

## 影响评估

- **对默认使用体验**：  
  - 现在通过 Feishu / 微信 / WhatsApp 等渠道直接对话时，默认进入的是通用 OpenClaw 助手人格，更符合「系统助手」预期。

- **对多 Agent 场景**：  
  - `shop-hunter` 等专用 Agent 仍然可用，只在显式路由或指定 Agent id 时才会被触发；  
  - 不会影响多 Agent Smart Shopper 相关脚本和 workspace 本身。

