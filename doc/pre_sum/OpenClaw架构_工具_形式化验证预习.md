# OpenClaw 架构、工具体系与形式化验证预习笔记

> 版本：2026.2.17（基于官方文档 `architecture` / `tools` / `security/formal-verification`）

---

## 1. 总览：OpenClaw 想解决什么问题？

- **核心定位**：用一个长期运行的 Gateway，将多通道消息（WhatsApp / Telegram / Slack / Discord / Signal / iMessage / WebChat 等）、多设备节点（macOS / iOS / Android / headless）与 LLM Agent 工具系统统一在一套安全、可控的“中枢”之上。
- **关键信念**：
  - 所有“高危能力”（shell、浏览器控制、节点远程执行等）必须通过 **显式工具调用 + 策略配置** 才能触达。
  - 安全不只靠实现，还要靠 **形式化模型** 把“系统应该保证什么”写成可执行的安全回归套件。
- **工程落地形态**：
  - 一个常驻的 **Gateway 守护进程**（WS + HTTP），负责所有外部通道、节点与工具调用的编排。
  - 多种 **客户端/控制平面**：CLI、macOS App、Web 管理端、自动化脚本等，通过 Gateway 的 WebSocket 协议交互。
  - 一套 **工具（Tools）系统**：为 Agent 提供受控的浏览器、文件系统、命令执行、Web 等能力，并可按模型/Agent/Provider 精细限制。
  - 一组 **形式化安全模型（TLA+）**：对授权、会话隔离、工具门控、配置错误等关键安全属性做可执行检查。

把这三个板块连在一起理解：  
**架构决定“系统边界 + 信任模型”，工具体系决定“能力暴露与约束方式”，形式化验证则是对这些安全设计做“机器检查 + 回归”的护栏。**

---

## 2. Gateway 架构与通信模型（architecture）

### 2.1 角色与职责划分

- **Gateway（守护进程）**
  - **唯一长期运行的中枢**：每台主机通常只需要一个 Gateway，负责与各消息通道、节点保持连接。
  - 提供：
    - HTTP 端点（默认 `18789`）：如 `/__openclaw__/a2ui/`、`/__openclaw__/canvas/` 等 UI/Canvas 相关静态内容。
    - WebSocket 端点：所有客户端/节点通过 WS 连接 Gateway。
  - 事件流：
    - 服务器向客户端推送：`agent`、`chat`、`presence`、`health`、`heartbeat`、`cron` 等事件。
    - 所有入站帧都会用 JSON Schema 校验，保证协议一致性。

- **Clients（控制平面客户端）**
  - 包括：macOS App、CLI、Web Admin、自动化脚本等。
  - 与 Gateway 的交互：
    - 订阅事件：`tick`、`agent`、`presence`、`shutdown` 等。
    - 发送请求：`health`、`status`、`send`、`agent`、`system-presence` 等。
  - 特点：**每个客户端一个长连接**，通过统一的 WS API 与 Gateway 通信。

- **Nodes（节点：macOS / iOS / Android / headless）**
  - 角色：`role: "node"`，在 `connect` 阶段声明自己的能力（caps/commands）。
  - 暴露能力示例：
    - `canvas.*`：驱动 Canvas（A2UI、前端展示等）。
    - `camera.*` / `screen.record`：采集相机或屏幕。
    - `location.get`：获取定位信息。
  - 安全特征：
    - 设备级身份：配对时确立“这是一台可信节点设备”，审批结果存入 pairing store。
    - 后续连接都带上设备 identity，实现“设备级信任”。

- **WebChat**
  - 相当于一个特殊客户端，前端通过 WS API 获取历史、发送消息。
  - 在远程部署场景会走与其它客户端相同的 SSH/Tailscale 通道。

### 2.2 连接生命周期（单个客户端）

连接建立有明确的 **状态机** 与 **强约束**：

1. **握手阶段**
   - 第一个帧必须是 `connect`，并携带：
     - 设备身份（包括是否是 node）。
     - 可选的 `auth.token`（如果 Gateway 开启 token 验证）。
   - 如果 `OPENCLAW_GATEWAY_TOKEN` 或 `--token` 已配置，则：
     - `connect.params.auth.token` 必须匹配，否则立即关闭连接。
   - 成功后：
     - 返回 `hello-ok` 快照：当前 presence + health 等基本状态。

2. **事件流阶段**
   - Gateway 向客户端持续推送：
     - `event:presence`（在线状态变更）
     - `event:tick`（心跳/节拍）
   - 客户端可以随时发起：
     - `req:agent`：触发某个 Agent 运行。
     - Gateway 先返回 `res:agent`（`status:"accepted"` 带 runId），再通过 `event:agent` 流式推送过程事件，最终 `res:agent` 带最终状态与 summary。

3. **关闭与错误**
   - 首帧不是合法 JSON 或不是 `connect` → 硬关闭。
   - 认证失败、协议违例也会直接关闭。

**场景理解**：  
- CLI/控制台就是围绕这个生命周期反复“发请求/收事件”，比如查看健康状态、启动 Agent、查看通道消息等。  
- 节点（node）也是一样的协议，只是 `role` 与可用工具不同。

### 2.3 Wire Protocol 关键点

- **统一帧结构**
  - 事件：`{type:"event", event, payload, seq?, stateVersion?}`
  - 请求：`{type:"req", id, method, params}`
  - 响应：`{type:"res", id, ok, payload|error}`

- **幂等性**
  - 对有副作用的请求（`send`、`agent`）需要带 **idempotency key**。
  - Gateway 维护短期去重缓存，保证在网络重试下不会重复执行副作用。

- **节点特有约束**
  - 所有 node 连接都必须以 `role:"node"` + 能力声明连接。
  - 有助于：
    - 工具路由到正确的 node。
    - 做安全策略（哪些 node 可以执行哪些命令）。

### 2.4 Pairing 与本地信任模型

- **统一认证入口：`gateway.auth.*`**
  - 无论是本地还是远程连接，都会经过 Gateway 的认证逻辑。
  - 可以配置：
    - 是否需要 token。
    - 非本地连接是否必须显式审批。

- **本地与远程的差异化策略**
  - 本地（loopback 或同一 Tailnet 地址）：
    - 可以配置为默认信任，提升本机 UX。
  - 远程：
    - 需要基于 `connect.challenge` 的签名完成配对。
    - 新设备 ID 必须人工批准。

- **Pairing Store**
  - 保存每个设备的配对状态、TTL、pending 上限等。
  - 与形式化模型中的“pairing store”安全属性（如 MaxPending、TTL 等）是一致的。

### 2.5 远程访问与运维

- **远程接入方式**
  - 推荐：Tailscale / VPN，确保 Gateway 仍在相对可信网络中。
  - 备选：SSH 隧道，例如：

    ```bash
    ssh -N -L 18789:127.0.0.1:18789 user@host
    ```

  - 即使是远程接入，也仍然使用同一套握手 + token 认证流程。

- **运维与健康检查**
  - 使用 `openclaw gateway` 命令启动/停止/重启。
  - 通过 `health` 方法或 `hello-ok` 快照查看健康。
  - 生产环境通常用 launchd/systemd 监管进程，保证自动重启。

### 2.6 架构设计的几个“安全不变量”

文档中提到的 **Invariants（不变量）** 是架构层的重要约束：

- 事件不会重放（不做事件回放），客户端必须用 `seq` 等机制自己发现丢失并刷新。
- 所有连接必须做握手，非法首帧直接关闭。
- 每台机器只有一个 Gateway 控制 Baileys（WhatsApp）会话，避免多 Gateway 争抢同一会话。

这些约束后面在 **形式化模型** 中会被进一步刻画，用来证明“在这些不变量下，某些攻击路径是被阻断的”。

---

## 3. Tools：Agent 能力暴露与策略控制（tools）

### 3.1 为什么要有“工具系统”

在 OpenClaw 的世界里：

- LLM 不直接“随意执行 shell / 打开浏览器 / 读写文件”，而是通过 **结构化的 Tools 调用** 完成。
- 每个工具都有：
  - 明确的输入参数 schema；
  - 清晰的返回类型；
  - 显式的安全策略（在哪些 Provider/Agent 下可用，是否支持 elevated 等）。

这套机制的目标：

- **减小能力面**：默认情况下只开启最小必要工具。
- **可审计**：所有高危操作都通过工具调用记录下来。
- **可验证**：形式化模型中的“工具门控”就依赖于此。

### 3.2 Global Tool Policy：`tools.allow` / `tools.deny`

在 `openclaw.json` 中：

- **全局控制**

  ```json5
  {
    tools: {
      allow: ["group:fs", "browser"],
      deny: ["group:runtime"]
    }
  }
  ```

  - `tools.allow`：允许哪些工具/工具组。
  - `tools.deny`：显式禁止（**deny 优先于 allow**）。
  - 支持 `*` 通配（`"*"` 表示所有工具），匹配不区分大小写。

- **实践场景示例**
  - 本地开发机：
    - 开启 `group:fs` + `group:runtime`，方便代码生成与脚本执行。
  - 生产客服 Bot：
    - 只开启 `message` + `sessions_*`，完整关闭 file/runtime/web 等工具。

### 3.3 Tool Profiles：内置工具基线

- `tools.profile`：在显式 allow/deny 前，先应用一个 **profile 基线**。
  - `full`：不做限制（等价于不设 profile）。
  - `messaging`：偏消息，主要包括：
    - `group:messaging`、`sessions_list`、`sessions_history`、`sessions_send`、`session_status`。
  - `coding`：偏开发：
    - `group:fs`、`group:runtime`、`group:sessions`、`group:memory`、`image`。
  - `minimal`：只有 `session_status`。

- **多层叠加关系**
  - 计算顺序大致是：
    1. profile（全局或按 Provider/Agent 的 profile）。
    2. `tools.byProvider` 收紧。
    3. 最后 `tools.allow` / `tools.deny` 叠加（deny 最终裁决）。

- **实践策略例子**
  - 全局默认 `coding`，但对某个客服 Agent：

    ```json5
    {
      tools: { profile: "coding" },
      agents: {
        list: [
          {
            id: "support",
            tools: { profile: "messaging", allow: ["slack"] }
          }
        ]
      }
    }
    ```

    - 整体环境仍是“可编程、可执行”的，但客服 Agent 只看得到消息相关工具。

### 3.4 Provider-Specific Tool Policy：按模型/Provider 收紧

- 使用 `tools.byProvider` 可以对某个 Provider 或具体模型精细收紧工具：

  ```json5
  {
    tools: {
      profile: "coding",
      byProvider: {
        "google-antigravity": { profile: "minimal" },
        "openai/gpt-5.2": { allow: ["group:fs", "sessions_list"] }
      }
    }
  }
  ```

  - 对可能不稳定或安全性质不明的 Endpoint：
    - 只暴露只读的 `group:fs`、`sessions_list` 等，避免高危操作。

- **场景**：
  - 主模型能力强但偏“激进”：只给少量 runtime 权限。
  - 某些 Provider 只用于检索/摘要：完全关闭 `exec`/`browser`。

### 3.5 Tool Groups：缩写与语义分组

主要内置分组（用于 allow/deny）：

- `group:openclaw`：所有内建工具（不含插件）。
- `group:nodes`：`nodes`。
- `group:messaging`：`message`。
- `group:automation`：`cron`、`gateway`。
- `group:ui`：`browser`、`canvas`。
- `group:web`：`web_search`、`web_fetch`。
- `group:memory`：`memory_search`、`memory_get`。
- `group:sessions`：所有 `sessions_*` 系列。
- `group:fs`：`read`、`write`、`edit`、`apply_patch`。
- `group:runtime`：`exec`、`bash`、`process`。

这些分组基本就是后续安全建模中“能力簇”的基础。

### 3.6 核心工具与典型使用场景

#### 3.6.1 `exec` / `process`：命令执行与进程管理

- **场景**：CI 辅助、脚本执行、本地项目编译、跑测试等。
- 关键参数：
  - `host`：`sandbox` / `gateway` / `node`（执行环境）。
  - `elevated`：是否以“提升权限”在 host 上直接跑。
  - `timeout` / `background` / `yieldMs`：控制执行时间与后台会话。
  - `security`：`deny` / `allowlist` / `full`。
- **风险与防护**：
  - 高危工具，通常必须：
    - 显式开启 `group:runtime`。
    - 结合 `tools.elevated` 与 `agents.list[].tools.elevated` 双重开关。
  - `process` 工具负责：
    - 列表、日志、轮询、终止、清理后台 session。

#### 3.6.2 `apply_patch`：结构化多文件编辑

- 提供“结构化 diff 应用”能力，适合多文件、多片段修改。
- 默认只允许 workspace 内写入（`workspaceOnly=true`），可以通过配置放宽，但不推荐。
- 实际场景：
  - 大型重构、批量代码修正。
  - 配合 `read`/`edit` 做更精细的修改。

#### 3.6.3 Web 工具：`web_search` / `web_fetch`

- **web_search**
  - 接 Brave Search。
  - 可以设置搜索条数，结果带缓存。
- **web_fetch**
  - 拉取网页内容并转换为 markdown/text。
  - 配合 Firecrawl 做 anti-bot 兜底。
- 场景：
  - Agent 做实时信息检索、资料收集。
  - 但仍然在 Tool Policy 里可以被整体关闭，用来保护隐私/成本。

#### 3.6.4 浏览器与 UI：`browser` / `canvas`

- `browser`
  - 控制专用的 OpenClaw 浏览器进程：
    - `navigate` / `act` / `snapshot` / `screenshot` / `status` / `start` / `stop` / `tabs` 等。
  - 多 profile 支持，端口区间 18800–18899。
  - 可路由到本机或远程 node（带 Playwright）。
- `canvas`
  - 驱动 A2UI / Canvas：
    - `present` / `hide` / `navigate` / `eval` / `snapshot` 等。
  - 底层通过 `node.invoke` 与节点交互。
- 场景：
  - 浏览器自动化测试、填表、抓取；结合飞书/Slack 等做“端到端”自动化。
  - 可视化结果展示、交互式 UI（A2UI）。

#### 3.6.5 `nodes`：节点能力与通知

- 能力包括：
  - `location_get`、`camera_snap`、`camera_clip`、`screen_record`。
  - `run`（macOS 的 `system.run`）、`notify`（系统通知）。
  - `pending` / `approve` / `reject` 用于 pairing。
  - `status` / `describe` 查看节点状态。
- 典型用法：
  - 把 Agent 和真实物理设备（办公 Mac、手机）打通，做自动化办公场景。
  - 所有敏感操作（拍摄/录屏）都要求前台、明确权限。

#### 3.6.6 消息与会话：`message` / `sessions_*` / `agents_list`

- `message`：
  - 对接各大 IM 平台，提供发消息、编辑、撤回、反应、拉群、踢人等。
  - “控制命令”与“普通消息”都走统一的消息路由。
- `sessions_*`：
  - 列出会话、查看历史、向其它会话发消息、衍生子会话等。
  - 支持 `sessions_spawn` 做“子 Agent”任务等。
- `agents_list`：
  - 列出当前 session 允许 spawn 的 Agent。

这些能力与 **routing/session isolation** 的形式化模型是强相关的：

- 放心做“多用户、多通道”的会话路由，同时依靠模型保证“不同 sender 的 DM 不会意外合并”。

#### 3.6.7 自动化与运维：`cron` / `gateway`

- `cron`：
  - 网关级定时任务：添加/更新/删除/立即运行/查看状态。
- `gateway`：
  - 远程重启、更新、获取配置 schema、应用配置补丁。

通常用于：

- 夜间批量任务、对账、周期性汇总。
- 在不 SSH 登上服务器的前提下，远程操作 Gateway。

### 3.7 插件与技能（Plugins + Skills）

- 插件（Plugins）
  - 在现有工具集合上再扩展功能（+ 新工具 + 新 CLI 命令）。
  - 例如：
    - LLM Task：结构化 JSON 工作流输出。
    - Lobster：有状态的工作流运行时，支持审批、恢复。
- 技能（Skills）
  - 对工具使用方式的提示文本，注入到 System Prompt 中，引导 LLM 正确调用工具。
  - 部分插件会自带 Skills，从而自动把“怎么用这个工具”教给模型。

---

## 4. 形式化验证：安全模型与实践价值（formal-verification）

### 4.1 目标与现状

- **目标（北极星）**：
  - 给出一套“机器可检查”的论证：
    - 在明确的前提下（正确部署、正确配置等），OpenClaw 能够实现它宣称的安全策略：
      - 授权（Authorization）
      - 会话隔离（Session Isolation）
      - 工具门控（Tool Gating）
      - 配置错误下的安全退化（Misconfiguration Safety）
- **现实落地形态（今天）**：
  - 一套 **可执行的、攻击者驱动的安全回归测试**，使用 TLA+/TLC 编写。
  - 每个“安全声明（claim）”：
    - 有一份“正向模型”（应为绿色 run）。
    - 有一份“负向模型”（刻画真实的 bug 类，TLC 应给出 counterexample trace）。

### 4.2 模型存放与运行方式

- 代码库：`vignesh07/openclaw-formal-models`

  ```bash
  git clone https://github.com/vignesh07/openclaw-formal-models
  cd openclaw-formal-models

  # Java 11+，仓库内自带 tla2tools.jar 与 bin/tlc
  make <target>
  ```

- 每个 `make <target>` 对应一个模型检查任务，覆盖不同安全属性。
- 当前运行是本地/CI 为主，未来可能：
  - 提供托管环境（小规模有界检查）。
  - CI 集成 + 公开 artifacts（日志、trace）。

### 4.3 一些关键安全场景与模型

下面是与架构/工具体系紧密相关的几类模型。

#### 4.3.1 Gateway 暴露与错误配置（Gateway Exposure）

- Claim：
  - 如果 Gateway 绑定到非 loopback 又没有启用 auth，远程攻击是可能的（模型中应存在攻击 trace）。
  - 一旦启用 token/password，模型中的“未经授权攻击者”无法成功建立会话。
- 相关目标：
  - `make gateway-exposure-v2-negative`：期望是 **红色（失败）**，说明模型刻画的“错误配置”确实导致安全问题。
  - `make gateway-exposure-v2-protected` / `make gateway-exposure-v2`：期望 **绿色**，表示在启用保护的情形下，攻击不再成功。

**和现实配置的映射**：  
你在 `openclaw.json` 中设置 `gateway.bindHost`、`gateway.auth.token` 等，就是这些模型里抽象出来的参数。  
形式化模型帮助你确认：“只要我满足这些条件，即使暴露到公网，也能挡住特定攻击族群”。

#### 4.3.2 `nodes.run` 高风险能力管道

- Claim：
  - 要执行 `nodes.run`（高危：相当于远程执行系统命令），必须满足：
    - 节点命令在 allowlist 中，并且节点声明了对应 command。
    - 若配置了人工审批，则必须通过实时审批，审批 token 不可重放（防止 replay）。
- 相关目标：
  - 负向模型：`make nodes-pipeline-negative` / `make approvals-token-negative` → 应该给出 counterexample。
  - 正向模型：`make nodes-pipeline` / `make approvals-token` → 应该绿色。

**实践含义**：  
OpenClaw 把“命令白名单 + 实时审批 + token 防重放”作为 `nodes.run` 的安全边界，你可以放心在架构层授予节点很强的能力，而不怕被简单绕过。

#### 4.3.3 Pairing Store：私聊门禁与配对上限

- Claim：
  - Pairing 请求必须尊重 TTL 与 pending 数量上限 `MaxPending`。
  - 即便在并发/重试下，也不能超额创建 pending rows。
- 相关目标：
  - 负向：`make pairing-cap-negative` / `make pairing-negative` 等。
  - 正向：`make pairing-cap` / `make pairing`。

**与架构的对应**：  
这确保“设备配对”不会因 race condition 或重复请求而产生无限 pending，避免恶意刷爆或者 DoS pairing store。

#### 4.3.4 Ingress Gating：提及（mention）与控制命令绕过

- Claim：
  - 在群聊要求“必须 @bot 才生效”的场景下，任何“控制命令”（如 `!restart` 类）都不能绕开 mention。
- 相关目标：
  - 负向：`make ingress-gating-negative`。
  - 正向：`make ingress-gating`。

**现实意义**：  
OpenClaw 的 routing 层可以做“必须被 @ 才执行控制命令”，模型保证了没有隐藏路径可以绕开这层 gating。

#### 4.3.5 Routing / Session Key Isolation：会话隔离

- Claim：
  - 来自不同 DM 发送者的消息，除非显式配置/链接（identityLinks），否则不会合并到同一个会话。
- 相关目标：
  - 负向：`make routing-isolation-negative`、`make routing-identitylinks-negative` 等。
  - 正向：`make routing-isolation`、`make routing-identitylinks`。

**安全含义**：  
确保“不同用户的私聊不会意外共享历史/上下文”，对于多租户、企业内部多账号场景非常关键。

#### 4.3.6 v1++ 模型：并发、重试、追踪正确性

这类模型进一步逼近真实世界：

- Pairing Store 并发/幂等性：
  - 模拟 `check-then-write` 非原子导致的竞争。
  - 要证明：在正确加锁/事务语义下，MaxPending 不会被绕过。
- Ingress 追踪与去重：
  - 在 provider 缺失 event ID 或重复推送的情况下：
    - 使用备用 key 去重；
    - 不会丢消息，也不会重复处理。
- Routing dmScope & identityLinks 优先级：
  - 证明 dmScope 嵌套配置时不会产生“会话交叉污染”。

这些模型共同作用的结果是：  
**即使在“重试 + 并发 + fan-out”这些实际系统容易踩坑的点上，OpenClaw 也有一套可执行的安全玻璃天花板。**

### 4.4 使用这些模型的实践建议

- 作为使用者/运维：
  - 不需要读懂所有 TLA+，但可以关注：
    - 文档里有哪些 **Assumptions（前提）**，例如必须配置 token、不允许某类绑定等。
    - 自己的部署是否满足这些前提。
  - 一旦准备在生产环境做“开放 Gateway / 高危节点能力 / 跨租户路由”等操作，最好：
    - 对照对应的模型说明，确认“哪些攻击路径已被验证过，哪些还没有”。

- 作为二次开发者：
  - 如果你改动了与安全相关的逻辑（routing、pairing、工具策略等）：
    - 理想流程是：先在模型仓库中调整/扩充对应模型，再跑一遍 `make`，最后再改代码。
    - 这会把“安全意图”写死在模型里，减少将来维护成本。

---

## 5. 三者之间的联动思路（学习路线建议）

结合这三个文档，建议的学习/实践路线：

1. **从架构入手**
   - 搭一个最小可用环境：本机 Gateway + 一个通道 + 一个节点。
   - 用 CLI/Web 控制台观察：
     - WS 连接过程（你可以通过日志看到 connect / hello-ok / event 流）。
     - 会话与消息流转。
2. **再深入工具体系**
   - 先只开 `group:messaging` + `group:fs`，从“安全的低权限 Agent”开始。
   - 再逐步开启 `group:runtime` / `browser` / `nodes`，体会：
     - 工具 profile、byProvider、按 Agent 限制的区别。
   - 结合你现有文档（飞书浏览器控制、Memory 机制、Gmail 集成等），把场景串起来。
3. **最后看形式化验证**
   - 不必一开始就读 TLA+ 原始代码，可以：
     - 先跑几条 `make gateway-exposure-*`、`make nodes-pipeline-*`，看看“红/绿”结果与文字说明。
     - 再偶尔展开一两个模型，看其 State/Action 是如何抽象真实系统的。
   - 当你对 OpenClaw 有修改或二开时，把“安全假设”写成你自己的小模型，是进阶方向。

总之：  
**Gateway 架构** 给出了统一的消息与设备中枢，**Tools 系统** 决定了 LLM 能做什么、能做到什么程度，**形式化验证** 则为这些安全设计装上了“机器监督”的安全网。掌握这三块，你就对 OpenClaw 的“设计边界”和“安全哲学”有了完整的一手认知。

