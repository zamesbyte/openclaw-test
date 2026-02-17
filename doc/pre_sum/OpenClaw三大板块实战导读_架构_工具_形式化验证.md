# OpenClaw 三大板块实战导读（架构 / 工具 / 形式化验证）

> 面向“要落地用起来”的工程视角，按官方三篇文档拆解：  
> - Architecture：Gateway 架构与连接模型  
> - Tools：工具能力与权限控制  
> - Formal Verification：安全模型与风险边界

---

## 一、Architecture：Gateway 架构与连接模型

### 1.1 Gateway 守护进程：所有东西的“总闸门”

- **应用场景**
  - 你希望本地或一台服务器上：
    - 统一管理 Telegram / WhatsApp / Slack / 飞书等聊天通道。
    - 统一管理各类节点（mac、iPhone、Android、headless node）。
    - 所有 Agent 都通过同一入口安全地调用这些能力。

- **实现原理（简化版）**
  - 在一台机器上跑一个长期存在的进程：`openclaw gateway`。
  - Gateway 暴露两个对外入口：
    - HTTP：默认 `http://127.0.0.1:18789/`，用于 Dashboard、A2UI、Canvas 等。
    - WebSocket：默认 `ws://127.0.0.1:18789`，所有客户端/节点都通过 WS 连上来。
  - 内部维护：
    - 与各消息 Provider 的连接（Telegram Bot、WhatsApp Baileys 等）。
    - 与各节点（Nodes）的 WebSocket 通道。
    - 与所有控制端（CLI / mac App / Web 管理端等）的 WebSocket 通道。

- **应用步骤（最小可用）**
  1. 在目标机器安装好 OpenClaw。
  2. 启动网关（示例）：
     - `openclaw gateway start`
  3. 用 Dashboard 或 CLI 确认状态：
     - `openclaw gateway status`
     - 浏览器打开 `openclaw dashboard` 给出的 URL。
  4. 后续所有通道（channels）、节点（nodes）、Agent 工具调用，都挂在这个 Gateway 上。

- **通俗小结**
  - 可以把 **Gateway 理解成“公司总前台”**：
    - 外面人（Telegram/WhatsApp 的消息）和里面人（你的节点设备、自动化脚本）都先到前台登记。
    - 前台统一做：身份验证、路由分发、日志审计。

---

### 1.2 三类连接角色：Client / Node / WebChat

- **应用场景**
  - 你会在不同位置看到三种“连到 Gateway 的家伙”：
    - 本地命令行 / 管理面板 → “Client”
    - 办公 Mac / iPhone 等 → “Node”
    - 浏览器里的聊天页面 → “WebChat”

- **实现原理**
  - 所有这些都是 WebSocket 客户端，唯一的区别是：
    - **Client**
      - 用来控制和观察：看状态、发 Agent 请求、看事件流。
      - 订阅事件（`tick` / `agent` / `presence` 等）+ 发送请求（`health` / `status` / `agent` 等）。
    - **Node**
      - 在 `connect` 时声明 `role: "node"` 和自己具备的能力列表。
      - 能执行 `canvas.*`、`camera.*`、`screen.record`、`location.get` 等命令。
      - 有单独的“配对流程”和设备身份。
    - **WebChat**
      - UI 比较花哨，但本质上只是一个“前端 Client”，用相同的 WS API 做聊天。

- **应用步骤（理解/排错用）**
  1. 看 Gateway 日志时，注意连接日志中的 `role` 字段：
     - 没有 `role` 或默认 → 一般是普通 Client。
     - `role: "node"` → 是节点连接。
  2. 遇到“节点收不到命令”时：
     - 先确认 node 是否连上 Gateway（`nodes status` 之类）。
     - 再确认 tools 配置中是否允许相关 node 工具。

- **通俗小结**
  - 可以粗暴记：
    - **Client = 操作台**（人/自动化在这里下指令）。
    - **Node = 工兵**（真正干活、拍照、录屏、跑命令的设备）。
    - **WebChat = 一个长得好看的 Client**（主要负责和人聊天）。

---

### 1.3 连接生命周期：从“打招呼”到“收事件”

- **应用场景**
  - 使用 CLI、控制台或节点时，经常会遇到连不上/被踢等问题。
  - 要理解“为什么会被踢”，需要知道 WebSocket 连接的生命周期。

- **实现原理（关键步骤）**
  1. **握手第一步：connect**
     - 每个新连接，第一帧必须是一个 JSON：`{ type: "req", method: "connect", ... }`。
     - 里面要带：
       - 设备身份（含是否是 node）。
       - 如果 Gateway 开了 token，还要带 `auth.token`。
  2. **认证与 hello-ok**
     - 如果 token 不对，Gateway 直接关连接。
     - 成功后，Gateway 回一个 `hello-ok` 快照：包含健康状态、当前在线信息等。
  3. **持续事件流**
     - 接下来 Gateway 会不断往下推：
       - `event:presence`（谁上线/下线）。
       - `event:tick`（心跳）。
       - `event:agent`（Agent 执行过程中的中间事件）。
  4. **关闭条件**
     - 首帧不是 JSON 或不是 connect → 硬关。
     - 认证不通过、违反协议 → 关。

- **应用步骤（排错心智模型）**
  1. 任何“连不上”的问题先问自己两个问题：
     - 我的第一个帧是不是合法的 `connect` 请求？
     - 我的 token（如果配置了）是不是和 `openclaw.json` 里的一致？
  2. 任何“命令没反应”的问题再问：
     - 连接握手后，有没有收到 `hello-ok`？
     - 后续有没有 `event:tick` 在刷？如果没有，说明连接断了。

- **通俗小结**
  - 可以把连接想象成“进门刷门禁 + 前台登记 + 定期打招呼”：
    - 第一次要刷卡（connect + token）。
    - 每隔一段时间前台会给你点个头（tick）。
    - 中途要是发现你身份不对或者随意乱闯，就把你请出去。

---

## 二、Tools：工具能力与权限控制

> 这一节完全对应官方 `Tools` 文档，重点：  
> - 工具开/关怎么配？  
> - 不同模型、不同 Agent 怎么做差异化授权？  
> - 每类工具典型用在什么场景？

### 2.1 工具总开关：tools.allow / tools.deny / profile

- **应用场景**
  - 想要：
    - 开启/关闭“某一类功能”，例如所有文件操作、所有命令执行。
    - 对生产环境做“只读 / 消息-only”的硬限制。

- **实现原理**
  - `openclaw.json` 里有一段：

    ```json5
    {
      tools: {
        profile: "coding",     // 先用一个基础模板
        allow: ["group:fs"],   // 再额外开
        deny: ["group:runtime"]// 再显式关（优先级最高）
      }
    }
    ```

  - 三层叠加：
    1. `tools.profile`：选一个“预设套餐”：
       - `full`：不限制。
       - `coding`：偏开发（文件、运行时等）。
       - `messaging`：偏聊天（消息、会话等）。
       - `minimal`：几乎关闭，只保留基本状态查询。
    2. `tools.byProvider`：对某个 Provider / 某个模型再收紧一轮。
    3. `tools.allow` / `tools.deny`：最后白名单 + 黑名单，`deny` 一票否决。

- **应用步骤（例子）**
  1. 开发机上，希望 Agent 能改代码、跑命令：
     - `profile: "coding"`
     - `allow` 不必加（coding 已经包含大多数开发需要）。
  2. 生产客服 Bot，只要聊天能力：

     ```json5
     {
       tools: {
         profile: "messaging",
         deny: ["group:runtime", "group:fs", "browser", "nodes"] // 明确全部禁止高危能力
       }
     }
     ```

  3. 对某个 Provider 比较“激进”，只给部分工具：

     ```json5
     {
       tools: {
         byProvider: {
           "openai/gpt-5.2": {
             allow: ["group:fs", "sessions_list"] // 只读文件 + 会话列表
           }
         }
       }
     }
     ```

- **通俗小结**
  - 工具权限可以理解成“先选一个套餐，再做加减菜”：
    - `profile` = 套餐。
    - `allow` = 加菜。
    - `deny` = 减菜（而且减菜优先级最高）。

---

### 2.2 工具分组：group:* 是怎么分能力“桶”的

- **应用场景**
  - 不想细抠某个工具名，就想说：
    - “给我所有文件相关的能力”
    - “关掉所有命令执行类功能”

- **实现原理**
  - `group:*` 是一组预定义的“能力桶”，比如：
    - `group:fs`：`read` / `write` / `edit` / `apply_patch`
    - `group:runtime`：`exec` / `bash` / `process`
    - `group:web`：`web_search` / `web_fetch`
    - `group:ui`：`browser` / `canvas`
    - `group:messaging`：`message`
    - `group:automation`：`cron` / `gateway`
    - `group:sessions`：整套 `sessions_*`
  - 当你在 `allow`/`deny` 里写 `group:fs`，就相当于一次性对那一整组工具生效。

- **应用步骤**
  1. 当你新打开一个项目，先看：
     - `openclaw config get tools.profile`
  2. 再看有没有：
     - `openclaw config get tools.allow`
     - `openclaw config get tools.deny`
  3. 根据自己的需求，改写成以 `group:*` 为主：
     - 调试时多开点（如 `group:fs`）。
     - 上线前多关点（如 `group:runtime`、`browser`）。

- **通俗小结**
  - 可以把 `group:*` 想象成“权限标签”：
    - 你不需要记住所有工具名字，只需要记：文件/运行时/消息/Web/UI/自动化/会话 这些标签。

---

### 2.3 高危能力一：exec / process（命令执行）

- **应用场景**
  - 在本地或 CI 里让 Agent：
    - 跑单元测试、打包前端、执行脚本、查看日志等。

- **实现原理**
  - `exec` 负责“发起命令”，`process` 负责“管理后台进程”：
    - `exec` 关键参数：
      - `host`: `sandbox`（受限环境） / `gateway`（网关主机） / `node`（某个节点）。
      - `elevated`: 是否走“提权路径”（在受限代理时才生效）。
      - `timeout`: 超时时间。
      - `background` / `yieldMs`: 是否变成后台会话。
    - `process`：
      - `list` / `poll` / `log` / `kill` / `clear` / `remove` 等。
  - 安全控制：
    - 必须先在 `tools` 配置里开 `group:runtime` 才能用。
    - `elevated` 还要额外开启 `tools.elevated` + `agents.*.tools.elevated`。

- **应用步骤（建议用法）**
  1. 本机调试：
     - 开发用 Agent → 开启 `group:runtime`。
     - 只在 **自己的机器** 上开 `host=gateway` / `elevated`。
  2. 生产环境：
     - 一般不建议给对外聊天 Agent 开 `exec`。
     - 如果一定要用（例如自动修复某些服务），推荐：
       - 单独配置一个内部 Agent。
       - 严格缩小工具允许范围（只开几个固定命令、路径）。

- **通俗小结**
  - 把 `exec` 当成“可以远程在服务器敲命令”的能力，威力极大：
    - 开在开发机可以让你偷懒，非常爽。
    - 开在生产客服机器人身上，如果没配好，就是“把命令行钥匙交给随机陌生人”。

---

### 2.4 高危能力二：browser / nodes / camera / screen

- **应用场景**
  - 想让 Agent：
    - 自动开浏览器填表、截图、点按钮。
    - 控制某台 Mac 截图、录屏、运行桌面命令。

- **实现原理**
  - `browser`：
    - 内部通过 Playwright 驱动一个持久化浏览器 Profile。
    - 提供 `start` / `open` / `navigate` / `screenshot` / `snapshot` / `act` 等子操作。
    - 可以在本机跑，也可以路由到某个支持浏览器的 node。
  - `nodes`：
    - node 端安装一个 OpenClaw 节点应用，连回 Gateway。
    - 暴露能力：
      - `camera_snap` / `screen_record` / `location_get` / `run` / `notify` 等。
    - 所有动作都走统一的 `node.invoke` 流程，可被工具策略控制。

- **应用步骤（以“远程控制办公 Mac”为例）**
  1. 在办公 Mac 上安装并运行 Node 客户端。
  2. 通过 pairing 流程把该设备配对到 Gateway。
  3. 在 `tools` 中：
     - 为某个内部 Agent 开：
       - `group:ui`（browser/canvas）。
       - `group:nodes`。
  4. 在聊天中让 Agent 执行：
     - `nodes` → `screen_record` / `camera_snap` / `run` 等。
     - 或 `browser` → `start` / `navigate` / `act` 等浏览器操作。

- **通俗小结**
  - 这部分就是“把 AI 的手脚伸到真实世界”的关键：
    - 浏览器 = 在网页世界点点点。
    - 节点 = 在真实设备上点点点、拍照、录屏。
  - 一定要配合严格的 `tools` 策略 + pairing 审批，用得好是生产力，用不好是“远程攻击放大器”。

---

### 2.5 消息与会话：message / sessions_* / agents_list

- **应用场景**
  - 做客服、群助手机器人，或多通道统一接入：
    - 需要在不同群/私聊里收发消息。
    - 需要在不同“对话 Session” 之间切换/派单。

- **实现原理**
  - `message`：
    - 封装了 Slack/Telegram/WhatsApp 等 IM 的：
      - 发消息、编辑、撤回、加反应、拉群、踢人、发投票等。
    - 对 Agent 来说，只看到一套统一的 `message` 工具，而不关心底层是哪一家。
  - `sessions_*`：
    - `sessions_list`：列出活动会话。
    - `sessions_history`：查看某会话历史记录。
    - `sessions_send`：从当前 Agent 向另一会话发一条消息。
    - `sessions_spawn`：衍生一个新的 Agent 会话去单独处理某个任务。
    - `session_status`：查看/修改会话状态（如强制用某个模型）。
  - `agents_list`：
    - 列出当前 session 可以 spawn 的 Agent 列表。

- **应用步骤（“主客服 + 专家子 Agent” 模式）**
  1. 用户在 Telegram 给“总客服机器人”发消息。
  2. 总客服 Agent 收到后，发现问题需要技术专家：
     - 调用 `sessions_spawn`，起一个“技术支持 Agent”子会话。
     - 技术支持 Agent 完成后，用 `sessions_send` 把总结结果发回主会话。
  3. 整个过程中：
     - 各会话历史互不泄露（依赖 routing/session isolation 模型保证）。

- **通俗小结**
  - 可以把 `message + sessions_*` 看成是：“公司里有多个处理窗口（会话），每个窗口背后可以排不同的专家（Agent），总台可以决定把哪个问题派给谁”。

---

## 三、Formal Verification：安全模型与风险边界

> 对应官方 `Formal Verification` 文档，核心不是“教你学 TLA+”，  
> 而是帮你搞清楚：**哪些安全属性已经被机器跑过模型了，哪些前提必须自己保证。**

### 3.1 模型长什么样？我需要做到什么程度？

- **应用场景**
  - 你准备：
    - 把 Gateway 暴露到公网；
    - 或者给节点很大权限（`nodes.run`、`screen_record` 等）；
    - 或者做多租户路由。
  - 想搞清楚：自己现在的用法有没有“踩到模型没覆盖的坑”。

- **实现原理（简述）**
  - 官方维护了一个独立仓库：`openclaw-formal-models`。
  - 里面有一堆用 TLA+ 写的模型，每个模型：
    - 限定一个有限状态空间（假设只有少量用户/请求/节点）。
    - 模拟各种攻击者行为和系统响应。
    - 通过 TLC（模型检查器）穷举所有可能路径。
  - 每个安全声明（claim）通常有：
    - 一个“正常版”模型：期望 run 结果为绿色（通过）。
    - 一个“负例版”模型：故意放松某些约束，期望出现红色（给出攻击 trace）。

- **应用步骤（轻量理解版本）**
  1. 打开文档，看每个模型前面的说明：“在什么前提下，想证明/反驳什么事情”。
  2. 把这些前提对应到自己的配置上：
     - 比如模型假设“Gateway 默认不对公网开放，或对公网必须配 token”，那你就不要自己反其道而行。
  3. 不一定要自己 `make` 模型，但可以用它们作为“安全设计文档”来读。

- **通俗小结**
  - 可以把这些模型看成：**官方对自己系统安全性的“单元测试 + 集成测试”，只是这次测试的是“安全逻辑”而不是函数逻辑**。

---

### 3.2 关键安全场景一：Gateway 暴露与错误配置

- **应用场景**
  - 你想让外网访问自己的 Gateway，比如：
    - 公司成员远程连回公司的 OpenClaw。
  - 但又担心一不小心“裸露在公网”被扫到。

- **实现原理（模型里证明的点）**
  - 模型区分两种情况：
    1. Gateway 绑定在公网地址 & 没开认证；
    2. Gateway 绑定在公网地址 & 配了 token/password。
  - 对第一种，负向模型会给出攻击者的成功路径（远程建立会话 → 发危险请求）。
  - 对第二种，正向模型证明：在给定假设下，匿名攻击者无法通过认证阶段。

- **应用步骤**
  1. 如果你确实要 `0.0.0.0:18789` 这种方式暴露 Gateway：
     - 必须设置强随机的 `gateway.auth.token`（或等价认证手段）。
  2. 建议配合：
     - Tailscale / VPN / SSH 隧道，再加一层网络级保护。
  3. 如有条件，可以拉模型仓库跑一遍相关 target：
     - 看看绿色/红色输出，帮助自己更直观地理解。

- **通俗小结**
  - 模型干的事情其实就是把一句“**不要裸奔到公网**”变成了一个经过穷举验证的、带反例的“严肃证明”。

---

### 3.3 关键安全场景二：nodes.run 高风险能力管道

- **应用场景**
  - 你想让 Agent 可以：
    - 在某台 Mac 上“执行系统命令”（构建、部署、重启服务等）。
  - 但这是最敏感的一类能力：一旦被滥用就是“完全沦陷”。

- **实现原理（模型关注的点）**
  - 模型中，`nodes.run` 要满足两个条件：
    1. 命令必须在节点声明的 allowlist 里。
    2. 如果要求人工审批，则必须经过审批流程：
       - 审批 token 不能被重放（反复使用）。
  - 负向模型模拟了一些错误设计：
    - 没有 allowlist；
    - 审批 token 可以被复用；
    - 审批与执行之间缺乏绑定关系等。

- **应用步骤**
  1. 实际配置时：
     - 永远不要给节点一个“任意命令”的白名单。
     - 为敏感命令开启审批流（例如只允许在有人确认时才执行部署脚本）。
  2. 设计自己的审批逻辑时：
     - 对照模型里的“负例”清单，避免掉入类似的坑（例如简陋的“yes/no 标志位”）。

- **通俗小结**
  - 一句话：**`nodes.run` 是“动生产”的大杀器，一定要配白名单 + 审批 + 防重放**。  
    模型只是帮你确认：在设计正确的情况下，这些防线确实能挡住模拟攻击者。

---

### 3.4 关键安全场景三：会话隔离与 mention 门禁

- **应用场景**
  - 多人群聊 / 多租户机器人：
    - 你不希望 A 群的指令影响 B 群；
    - 要求“必须 @bot 才执行控制命令”；
    - 不同用户的私聊 DM 不应该串线。

- **实现原理（模型里检查的东西）**
  - Ingress Gating：
    - 在要求 mention 的群组里：任何控制命令都必须在有 @bot 的前提下才有效。
    - 模型验证没有谁能“绕过 mention 直接发控制命令”。
  - Routing / Session Key Isolation：
    - 每个 DM 会话有自己的 session key。
    - 只有配置了 identityLinks 时，某些身份才被明确合并。
    - 模型检查在各种配置下不会出现“会话混串”的情况。

- **应用步骤**
  1. 在配置渠道/路由规则时：
     - 明确哪些群必须 @ 才触发命令。
     - 明确哪些频道/身份被允许合并到同一会话。
  2. 遇到奇怪的“串线”问题时：
     - 优先看 routing/dmScope/identityLinks 的配置，而不是怀疑模型没覆盖。

- **通俗小结**
  - 可以理解为：**模型帮你证明“默认情况下，各自的 DM 和群聊是互不干扰的”，只有你显式写了“要合并”才会合并。**

---

### 3.5 关键安全场景四：并发、重试和去重

- **应用场景**
  - 实际生产环境里会遇到：
    - Provider 重复推送同一事件；
    - 高并发下 pairing 请求互相打架；
    - 一条外部事件 fan-out 成多条内部消息。

- **实现原理（模型怎么抽象这些问题）**
  - Pairing 并发模型：
    - 模拟“检查当前 pending 数量 → 再写入新记录”的一整套流程。
    - 如果没有原子性，很容易越过 MaxPending。
    - 正向模型要求：无论怎么并发，都不能超出 MaxPending。
  - Ingress 去重/追踪模型：
    - Provider 有时提供 event ID，有时没有。
       - 模型要求：在没有 ID 时，使用安全的 fallback key 去区分事件。
    - 在有重试时，不能把同一事件当成两条处理。

- **应用步骤**
  1. 设计/修改数据库操作时：
     - 尽量使用带事务的“检查 + 写”组合，而不是多次分离操作。
  2. 处理外部事件时：
     - 尽可能利用 Provider 的 event ID 或 trace ID；
     - 在日志里保持同一 trace ID 贯穿全链路，方便排错。

- **通俗小结**
  - 这类模型的目标很朴素：**确保在现实世界常见的“抖动 + 重试 + 并发”场景下，系统不会悄悄违反它本来承诺的安全/配额约束。**

---

## 四、小结：按这份文档怎么学、怎么用？

- **从架构开始**
  - 搭好 Gateway，理解三类角色（Client / Node / WebChat）和连接生命周期。
  - 至少自己动手跑一遍：启动 Gateway、连一个通道、连一台节点。
- **再去玩工具**
  - 先只开 `messaging + fs`，从“安全低权限”起步。
  - 熟悉后再按需打开 `runtime`、`browser`、`nodes`，始终记着：这些是高危能力。
- **最后看安全模型**
  - 不必精通 TLA+，但要知道每个模型在帮你守哪道门、有哪些前提条件。
  - 当你计划“开公网 / 给节点大权限 / 做多租户”，先对照对应模型的假设再动手。

一句话版总结：  
**Architecture** 告诉你 OpenClaw 的“骨架和血管”，**Tools** 决定这套身体能伸出哪些“手脚”，**Formal Verification** 则是在不断用模型和测试确认：这具身体在各种极端情况下不会“自己打自己”或“被别人轻易控制”。把这三块串起来，你就能又安全、又高效地用 OpenClaw 落地真实业务。  

