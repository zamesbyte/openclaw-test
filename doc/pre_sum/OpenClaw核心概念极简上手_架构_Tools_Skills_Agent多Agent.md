# OpenClaw 核心概念极简上手（架构 / Tools / Skills / Agent 多 Agent）

> 目标：给“要上手用 OpenClaw 做业务”的人看，少概念，多场景。  
> 只抓最关键的几个问题：  
> 1. Gateway 架构到底干嘛的？  
> 2. Tools / Skills 是怎么让模型“安全地会用工具”？  
> 3. 一个 Agent 和多 Agent 各自适合什么场景，怎么配置？  
> 4. sessions / sub-agents（多 Agent 协作）能帮你实现什么效果？

---

## 一、Architecture：Gateway = “总控后台”

### 1.1 Gateway 是什么？

- **应用场景**
  - 你有很多入口：飞书、Telegram、WhatsApp、Slack、WebChat、Gmail Webhook……
  - 你还有很多“执行手”：本机、办公 Mac、云上的 headless node、浏览器自动化……
  - 希望所有消息、命令、工具调用，都走一条主干，方便统一管理和加安全。

- **实现原理（白话版）**
  - 在一台机器上长期跑一个进程：`openclaw gateway`。
  - 它提供两个主要入口：
    - **HTTP**（默认 `http://127.0.0.1:18789/`）：Dashboard、A2UI、Canvas 等。
    - **WebSocket**（默认 `ws://127.0.0.1:18789`）：所有客户端和节点都用 WS 连上来。
  - 连上来之后，大家都通过同一套 JSON 协议发请求 / 收事件。

- **你实际要做什么**
  1. 在一台“中枢机”（本机或服务器）执行：
     - `openclaw gateway start`
  2. 用 CLI 或 Dashboard 看状态：
     - `openclaw gateway status`
     - `openclaw dashboard`（自动带 token 打开控制台）
  3. 后面无论是接飞书、接 Telegram、连节点，都是先保证 Gateway 在跑。

- **一句话小结**
  - 把 Gateway 当成“所有 AI 能力的 **总路由器 + 安全大门**”。  
    没有 Gateway，OpenClaw 就只是一堆工具；有了它，这些工具才能变成一个系统。

---

### 1.2 三类“连进来”的角色：Client / Node / WebChat

- **应用场景**
  - 你会看到很多不同入口连到 Gateway：
    - 终端命令行、Web 管理后台 → 你自己在操作。
    - 办公 Mac / iPhone / Android → 你想远程控制的设备。
    - 浏览器里的聊天页面 → 用户直接和机器人聊天。

- **实现原理**
  - 这三类本质都是 “WebSocket 客户端”，区别只在于**角色和能力**：
    - **Client**（控制台 / CLI / 后台）
      - 看健康状态、看日志、发 Agent 任务。
      - 收事件：`agent`、`presence`、`health` 等。
    - **Node**（设备）
      - 在连接时声明 `role: "node"` + 支持的命令，比如 `camera_snap`、`screen_record`、`system.run`。
      - Gateway 记住这台设备的身份和权限。
    - **WebChat**
      - 一个“好看一点的 Client”，本质也是用 WS 和 Gateway 聊天。

- **你实际要做什么**
  - 当你：
    - 在 CLI 里跑命令时，其实是一个 Client。
    - 在办公 Mac 上装 Node 程序时，就是注册了一个 Node。
    - 打开 Web 聊天页面时，其实也是一个 Client，只是包了 UI。

- **一句话小结**
  - **Client = 控制台**，**Node = 执行手**，**WebChat = 给人用的聊天界面**，全都通过 Gateway 这一个入口说话。

---

## 二、Tools：给模型开的“能力开关”

> 模型本身只会“说话”。Tools 是给它开的“手脚”。  
> Tools 决定：**模型能不能看文件、跑命令、开浏览器、控制节点……**  
> 所有危险能力都必须在 Tools 层明确打开。

### 2.1 基本认识：Tools 都有哪些大类？

- **文件类（group:fs）**
  - `read` / `write` / `edit` / `apply_patch`
  - 用于：看代码、改代码、写配置。
- **命令类（group:runtime）**
  - `exec` / `bash` / `process`
  - 用于：跑脚本、起服务、查看日志等。
- **Web 类（group:web）**
  - `web_search` / `web_fetch`
  - 用于：搜索资料、抓网页内容。
- **浏览器 & UI（group:ui）**
  - `browser` / `canvas`
  - 用于：浏览器自动化、A2UI 画界面。
- **消息 & 会话**
  - `message` / `sessions_list` / `sessions_history` / `sessions_send` / `sessions_spawn`
  - 用于：发消息、多会话路由、多 Agent 协作。
- **节点 & 自动化**
  - `nodes` / `cron` / `gateway`

只要记住这些“桶”（group），就能快速控制一整类能力。

---

### 2.2 Tools 开关：profile + allow + deny

- **应用场景**
  - 本机想“什么都能干”；
  - 生产客服 Bot 只能“聊天，不许乱动机器”；
  - 某个模型只想让它“看文件，不让它跑命令”。

- **实现原理**
  - `openclaw.json` 里有一段类似：

    ```json5
    {
      tools: {
        profile: "coding",
        allow: ["group:fs"],
        deny: ["group:runtime", "browser", "nodes"]
      }
    }
    ```

  - 生效顺序可以简单理解为：
    1. **profile**：先选一个“基础套餐”（`full` / `coding` / `messaging` / `minimal`）。
    2. **allow**：在套餐基础上再“加菜”。
    3. **deny**：最后“减菜”（deny 永远优先级最高）。

- **你实际要做什么（常见两种环境）**
  1. **开发环境（本机）**
     - `profile: "coding"`
     - 不特意 deny：让 Agent 能读写文件、跑命令、开浏览器。
  2. **生产客服 Bot**

     ```json5
     {
       tools: {
         profile: "messaging",
         deny: ["group:runtime", "group:fs", "browser", "nodes", "cron", "gateway"]
       }
     }
     ```

     - 让它只会发消息、查会话，完全碰不到系统层面。

- **一句话小结**
  - Tools 配置就是：“给这个 Agent 开多少刀？”  
    开得越多，能力越强，但也越危险；profile+allow+deny 就是在做“外科级切分”。

---

## 三、Skills：教模型“怎么用这些工具”

> Tools = 能力接口；**Skills = 使用说明书 + 命令入口**。  
> 没有 Skills，模型只知道“有个工具叫 exec”；  
> 有了 Skills，模型会知道“怎么用 exec 做某个具体任务、需要注意什么风险”。

### 3.1 Skills 的基本概念

- **形态**
  - 每个 Skill 是一个目录，里面有一个 `SKILL.md`。
  - `SKILL.md` 中有 YAML 头（`name` / `description` / `metadata` 等）+ 文字说明。
  - OpenClaw 会把这些说明以紧凑 XML 的方式塞进 System Prompt，让模型“提前读一遍说明书”。

- **加载位置与优先级**
  - Workspace skills：项目内 `./skills` （**优先级最高**，每个 Agent 自己的技能）。
  - 本地 managed skills：`~/.openclaw/skills`（多个 Agent 共享）。
  - Bundled skills：随着 OpenClaw 一起安装的内置技能（优先级最低）。
  - 还有 `skills.load.extraDirs`：可以额外挂一堆技能目录。

  冲突时：`./skills` > `~/.openclaw/skills` > 内置。

---

### 3.2 Skills 和 Tools、插件的关系

- **Skills 不直接“提供能力”**，能力来自 Tools。
- Skills 主要做三件事：
  1. 文本层面给模型讲清楚：**什么时候应该用哪个 Tool，用法是什么**。
  2. 有的 Skill 会把某个 Tool 绑定成 Slash 命令（`/xxx`），让人/模型都能通过命令调用。
  3. 插件可以自带 Skills：比如某个 Voice Call 插件既提供 Tool，又自带 Skill 教模型如何发起通话。

- **ClawHub：技能市场**
  - `https://clawhub.com` 是公开技能仓库。
  - 常见操作：
    - `clawhub install <skill-name>` 安装到当前工程的 `./skills`。
    - `clawhub sync --all` / `clawhub update --all` 做更新/同步。

---

### 3.3 Skills 的安全和过滤

- **加载时过滤（metadata.openclaw.requires.*）**
  - Skill 可以声明：
    - 需要哪些 env（比如 `GEMINI_API_KEY`）。
    - 需要哪些配置项为 true（比如 `browser.enabled`）。
    - 需要哪些二进制在 PATH 里（比如 `uv`、`gemini`）。
  - 不满足就不加载，避免“Skill 乱提示用不到的工具”。

- **配置覆盖（skills.entries）**

  ```json5
  {
    skills: {
      entries: {
        "nano-banana-pro": {
          enabled: true,
          apiKey: "GEMINI_KEY_HERE",
          env: { GEMINI_API_KEY: "GEMINI_KEY_HERE" }
        },
        "some-skill": { enabled: false }
      }
    }
  }
  ```

  - 可以对单个 Skill：
    - 打开/关闭；
    - 注入 env / apiKey；
    - 传入自定义配置。

- **一句话小结**
  - Tools 决定“能不能做这件事”；Skills 决定“模型会不会做这件事、会不会做错”。  
  - 对第三方 Skill，要当作代码看：**看一眼再开**。

---

## 四、Agent 与多 Agent：一个大脑 vs 一群专门的大脑

> 这一部分对应：  
> - `openclaw agents` CLI  
> - `Multi-Agent Routing`  
> - `Session Tools` / `Sub-agents`

### 4.1 什么是“一个 Agent”？

- **一个 Agent = 一个“完整大脑 + 档案 + 记忆”**
  - 自己的 session 存储：`~/.openclaw/agents/<agentId>/sessions`
  - 自己的 `agentDir`：里面有 auth profiles（各 Provider 的 token）、模型配置。
  - 自己的 workspace：代码、文档、`AGENTS.md` / `SOUL.md` / `USER.md` 等人格文件。
  - 自己的技能（`./skills`），可叠加共享技能（`~/.openclaw/skills`）。

- **单 Agent 场景**
  - 个人日用：所有飞书/Telegram/WhatsApp 都路由到一个 Agent（`main`）。
  - 小团队 Demo：只用一个“万能助手”，不区分角色。

- **你实际用到的命令**

  ```bash
  # 查看已有 Agent
  openclaw agents list

  # 新建一个 Agent（work）
  openclaw agents add work --workspace ~/.openclaw/workspace-work

  # 设置 Agent 的名字、头像等
  openclaw agents set-identity --agent work --name "Work Bot" --emoji "💼"
  ```

---

### 4.2 多 Agent 路由：一个 Gateway，同事/家庭/业务各一套大脑

- **业务应用场景**
  1. 一个 Gateway 上：
     - `home`：个人生活助手（家庭群、个人 WhatsApp）。
     - `work`：公司内部助手（公司 Telegram、企业微信/飞书）。
  2. 一个 WhatsApp 号码，但不同好友 DM 路由到不同 Agent（不同人共用一个号）。
  3. 不同通道绑定不同“人格”：
     - WhatsApp：轻量 Chat 模型。
     - Telegram：用于深度分析的 Opus 模型。

- **关键配置：`agents.list` + `bindings`**

  ```json5
  {
    agents: {
      list: [
        {
          id: "home",
          default: true,
          workspace: "~/.openclaw/workspace-home"
        },
        {
          id: "work",
          workspace: "~/.openclaw/workspace-work"
        }
      ]
    },
    bindings: [
      // WhatsApp 个人号 → home
      { agentId: "home", match: { channel: "whatsapp", accountId: "personal" } },
      // WhatsApp 商业号 → work
      { agentId: "work", match: { channel: "whatsapp", accountId: "biz" } }
    ]
  }
  ```

  - `bindings` 规则：谁先匹配谁生效，越具体优先级越高（peer > accountId > channel）。

- **你能达到什么效果**
  - 一台服务器，一个 Gateway：
    - 既能当“个人助手”，又能当“公司机器人”，数据和人格互不干扰。
  - 想把某个群/某个 DM 路由给另一个 Agent，只要新加一条 `bindings` 规则。

- **一句话小结**
  - 多 Agent 路由就是：**一个 Gateway 像“总机”，不同来电自动分配给不同分机（Agent）**。

---

### 4.3 多 Agent + Session Tools：跨会话、跨 Agent 协作

- **业务应用场景**
  1. 总客服 Agent 接到复杂问题 → 丢给“技术 Agent”处理 → 拿回总结发给用户。
  2. 一个“调度 Agent”管理多个“执行 Agent”（比如搜索 Agent、代码 Agent）。

- **关键工具**
  - `sessions_list`：列出当前 Agent 可见的会话。
  - `sessions_history`：查看某个会话的聊天记录。
  - `sessions_send`：往别的会话发一条消息（包括别的 Agent 的会话）。
  - `sessions_spawn`：起一个“子 Agent 会话”（下节详细说）。

- **基本思路**
  - 当前会话（Session A）里，你可以：
    - 用 `sessions_list` 找到另一个 Session B。
    - 用 `sessions_send` 对 B 说：“帮我总结一下你那边的情况，结果发回来”。
    - 最终 B 跑完，结果通过 announce 再回到 A。

- **安全与边界**
  - 可见范围由 `tools.sessions.visibility` + sandbox 设置控制：
    - `self` / `tree` / `agent` / `all`。
  - 多 Agent 之间的互相发送，还受 `tools.agentToAgent` 和 allowlist 控制。

- **一句话小结**
  - Session Tools 让一个 Agent 不只是“自己干活”，还可以“给别的 Agent 下任务、看别人的进度”。

---

### 4.4 Sub-agents（`sessions_spawn`）：起“子任务 Agent”

- **业务应用场景**
  1. 主对话里有一个“慢任务”（长时间研究、批量处理），不想堵住当前聊天。
  2. 想实现“调度 Agent”（orchestrator）+ 多个“工人 Agent”（worker）并行干活。

- **实现原理（简化）**
  - `sessions_spawn` 会：
    1. 创建一个新的会话（`agent::subagent:`）。
    2. 在那个会话里跑一次完整的 Agent 任务（可以指定 `agentId` / `model` / `thinking`）。
    3. 跑完之后，发一条“announce 消息”回到原来的聊天（告诉你结果、耗时、token 等）。
  - 默认行为：
    - 对你来说是非阻塞的：立即返回 `{status:"accepted", runId,...}`。
    - 子会话过一段时间自动归档（默认 60 分钟）。

- **关键参数（常用）**
  - `task`：必须写清楚子 Agent 要做的事。
  - `agentId`：可以让子任务挂到另一个 Agent 上执行（需 allowlist 放行）。
  - `model`：给子任务用一个更便宜/更适合的模型。
  - `runTimeoutSeconds`：超时自动中止子任务。
  - `cleanup`：`keep` 或 `delete`（宣布结果后是否立即归档）。

- **多层嵌套（orchestrator 模式）**
  - 配置 `agents.defaults.subagents.maxSpawnDepth = 2`，可以：
    - 主会话 → 调度子 Agent → 再起多个“工人子子 Agent”。
  - 防炸：
    - `maxChildrenPerAgent`：每个会话最多多少个子任务。
    - `maxConcurrent`：全局子任务并发上限。

- **你能做出的效果示例**
  - “主聊天”负责跟你对话；
  - 背后悄悄起一堆 sub-agents 去：
    - 多源搜索 + 汇总；
    - 针对不同代码仓分别改 PR；
    - 不同业务线各跑一份日报，然后帮你合并。

- **一句话小结**
  - `sessions_spawn` 就是：**给当前对话“开后台任务”，任务跑完自动回来汇报**；  
    配合多 Agent，就能做出真正的“Agent 团队协作”。

---

## 五、如何用这份文档快速开始？

- **如果你刚接触 OpenClaw**
  1. 先把 Gateway 跑起来，确认 `openclaw gateway status` 正常。
  2. 配一个最简单的单 Agent + 一个通道（例如 Telegram 或飞书）。
  3. 只给这个 Agent 开 `group:messaging` + `group:fs`，熟悉基本聊天和看/改文件。

- **然后逐步升级**
  1. 开 `group:runtime`，让它能帮你跑本地脚本（但只在开发机开）。
  2. 配 Node + browser，让它能帮你自动点网页、截屏、录屏。
  3. 根据业务拆分多个 Agent，用 `bindings` 把不同通道/群/DM 分配给不同 Agent。
  4. 用 Session Tools + Sub-agents 做“一个主 Agent 调度多个子 Agent 干活”的模式。

- **最后思考安全**
  - 想开放公网访问、想给节点很大权限、想多租户混跑时：
    - 回头看一下官方的 Formal Verification 文档，看一眼：
      - 哪些安全属性是有模型支撑的；
      - 你的部署有没有违背前提（比如没配 token 就绑公网）。

如果你愿意，我可以在这份“极简上手”基础上，再针对你已有的几个总结文档（飞书浏览器、Memory、Gmail 集成等），分别写成同样风格的“场景/原理/步骤/小结版”，形成一整套连贯的 OpenClaw 实战手册。  

