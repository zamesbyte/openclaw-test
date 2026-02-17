# 多 Agent Smart Shopper 场景总览（原理 / 实战 / 调度模板）

> 本文合并并整理了以下四篇文档的全部内容，并按实际代码实现（尤其是当前 `~/.openclaw/openclaw.json` 与 `scripts/multi-agents-setup.sh` 行为）做了少量冲突修正：  
> - `多Agent调度与Prompt模板_SmartShopper.md`  
> - `多Agent全网比价助手实战.md`  
> - `多Agent写作与协作原理_通俗讲解.md`  
> - `多Agent写作与协作原理.md`

---

## 一、场景与角色概览

### 1.1 Smart Shopper Protocol 场景回顾

- **用户需求**：我要买一个贵数码（例如 `Sony WH-1000XM5`），  
  想知道各平台当前最低价，还要避开“翻新机 / 假货 / 口碑差”的店。
- **三类能力**：
  - **浏览器搜价**：打开 Amazon / eBay / 京东 / 淘宝网页版，找到最低价候选。
  - **全网查口碑**：到 Reddit / 论坛 / 什么值得买等搜索卖家黑历史。
  - **汇总与落地**：综合价格 + 风险，出最终 Markdown 报告文件。

在 OpenClaw 中，我们通过 3 个专职 Agent 来实现协同：

- `shop-hunter`：赏金猎人，负责浏览器搜价。
- `shop-skeptic`：鉴谎师，负责查黑历史与风险评估。
- `shop-auditor`：审计员，负责汇总、做表格、写报告（兼 orchestrator，对接用户）。

---

## 二、OpenClaw + 多 Agent + 大模型的关系（技术视角）

### 2.1 核心组件角色

- **Gateway（网关守护进程）**
  - 常驻进程（`openclaw gateway`），统一管理：
    - 各聊天通道（飞书、Telegram、WhatsApp 等）的连接与消息；
    - 各节点（Nodes）的连接（macOS/iOS/Android/headless）与命令执行；
    - 工具调用（Tools）的权限与路由。
  - 对外提供：
    - HTTP 入口（Dashboard、A2UI 等）；
    - WebSocket 入口（所有客户端和节点都通过 WS 连接）。

- **Agents（多 Agent 大脑）**
  - 每个 `agentId` 是一套独立“人格 + 工作区 + 会话”的组合：
    - 自己的 workspace（文件、prompt、技能等）；
    - 自己的 session 存储（历史对话与路由状态）；
    - 自己的 auth 配置和模型偏好；
    - 自己的 tools / sandbox 策略。
  - Gateway 负责将“某条入站消息”根据 `bindings` 路由到对应 `agentId`。

- **LLM 提供商（大模型）**
  - 例如 OpenAI / Anthropic / Qwen / Gemini 等。
  - OpenClaw 根据 Agent 配置选择具体模型（包括 thinking level、是否支持 tools 等），
    并负责把 System Prompt + Skills + 可用 Tools schema 等打包发给模型。

- **Tools / Skills**
  - **Tools**：结构化能力接口（读写文件、跑命令、浏览器、Web 搜索、nodes 等）。
  - **Skills**：教模型“什么时候、如何安全地使用这些工具”的说明书和命令入口。
  - Tools 是“能力边界”，Skills 是“使用方法”。

### 2.2 调用流程（简化）

1. 用户在某通道发消息 → Gateway 收到 → 根据 `bindings` 找到目标 `agentId`。
2. Gateway 为该 Agent 构造 Prompt：
   - 读取 Agent workspace 中的 `AGENTS.md` / `SOUL.md` / Skills 列表；
   - 注入可用工具（按全局和 per-agent tools 策略收敛后）；
   - 结合部分历史对话上下文。
3. Gateway 将请求发给对应的大模型（带上 tools schema）。
4. 模型在对话中根据需要调用 Tools；Gateway 执行 Tools，并将结果返回给模型；
5. 模型产生最终回复；Gateway 发回到用户所在通道。

---

## 三、一个 Agent 的“内部结构”（以审计员为例）

以 `shop-auditor` 为例，一个 Agent 通常至少包含：

1. **配置层（openclaw.json → agents.list[]）**
   - `id`：`shop-auditor`
   - `workspace`：`~/.openclaw/workspace-shop-auditor`
   - `identity`：名字、emoji、头像等。
   - `tools`：该 Agent 可以使用哪些工具（以及哪些被 deny）。
   - `subagents`（可选）：允许该 Agent 通过 `sessions_spawn` 调用哪些其他 Agent。

2. **workspace 层（文件系统）**
   - `AGENTS.md`：这类 Agent 的“岗位说明书”和写作风格。
   - 其他可选文件：`SOUL.md`（人格设定）、`USER.md`（主人偏好）、`skills/` 等。

3. **运行时行为**
   - 当 Gateway 把一条消息路由到 `shop-auditor`：
     - 加载其 workspace Prompt（AGENTS 等）；
     - 注入已允许的工具（例如 `group:fs`、`sessions_spawn` 等）；
     - 交给模型决定是否调用子 Agent（通过 `sessions_spawn`）或直接操作文件。

从实现角度看：**Agent = 配置 + workspace + Prompt + 工具权限**，  
Gateway 把“入站消息”转成“对这个 Agent 的一次模型调用 + 一堆可选工具调用”。

---

## 四、Smart Shopper 三个 Agent 的实现原理

> 相关脚本：`scripts/multi-agents-setup.sh`（会在 `agents.list` 中写入 3 个 Agent，并为每个 Agent 创建 workspace 与 AGENTS.md）。

### 4.1 shop-hunter：赏金猎人（Browser 搜价）

- **职责**
  - 专注浏览器自动化，从多个电商网站中找到候选最低价：
    - 平台（Amazon / eBay / 京东 / 淘宝等）；
    - 价格；
    - 卖家名称；
    - 商品链接。

- **关键配置点**
  - `agents.list[].id = "shop-hunter"`
  - `workspace = ~/.openclaw/workspace-shop-hunter`
  - `tools`（当前脚本写入逻辑）：
    - `profile: "coding"`：基础能力偏开发和自动化；
    - `allow: ["browser"]`：显式允许浏览器工具；
    - `deny: ["group:runtime", "nodes", "cron", "gateway"]`：禁止高危命令、节点调用、系统级操作。

- **AGENTS.md 内容要点**
  - 只关心价格、链接、卖家，不做口碑判断；
  - 优先使用 `browser` 工具进行页面导航、搜索和信息提取；
  - 尽量输出结构化结果（JSON 数组或 Markdown 表格）。

### 4.2 shop-skeptic：鉴谎师（Search & Reasoning）

- **职责**
  - 对候选卖家或链接做“口碑审查”：
    - 搜索负面评价、投诉记录；
    - 汇总成“风险等级 + 证据”。

- **关键配置点**
  - `agents.list[].id = "shop-skeptic"`
  - `workspace = ~/.openclaw/workspace-shop-skeptic`
  - `tools`：
    - `profile: "coding"`
    - `allow: ["group:web"]` → `web_search` / `web_fetch` 等；
    - `deny: ["group:runtime", "browser", "nodes"]` → 不允许跑命令或自己开浏览器。

- **AGENTS.md 内容要点**
  - 偏保守，有一点“杞人忧天”，宁可多怀疑；
  - 善用搜索工具从 Reddit、论坛、什么值得买、贴吧等抓取文本；
  - 对每个候选项给出：
    - 风险等级（低 / 中 / 高）；
    - 简短理由与证据引用。

### 4.3 shop-auditor：审计员（Orchestrator + File I/O）

- **职责**
  - 作为唯一与用户对话的入口：
    - 接受用户自然语言需求（比如“帮我比较 Sony WH-1000XM5”）；
    - 调度两个专业子 Agent 完成实质工作；
    - 汇总结果，生成 Markdown 报告文件并给出结论。

- **关键配置点**
  - `agents.list[].id = "shop-auditor"`
  - `workspace = ~/.openclaw/workspace-shop-auditor`
  - `tools`（当前脚本写入逻辑）：
    - `profile: "coding"`
    - `allow: ["group:fs", "sessions_spawn", "sessions_history", "sessions_list"]`
      - `group:fs`：支持文件读写，落地 Markdown 报告；
      - `sessions_spawn` / `sessions_history` / `sessions_list`：用于管理子 Agent 会话。
    - `deny: ["browser", "nodes", "cron", "gateway"]`
      - 不让它直接“碰机器”，所有访问能力都绕过子 Agent。
  - `subagents`：

    ```json5
    {
      "subagents": {
        "allowAgents": ["shop-hunter", "shop-skeptic"]
      }
    }
    ```

    - 意味着审计员可以通过 `sessions_spawn` 起这两个 Agent 的子任务。

- **AGENTS.md 内容要点**
  - 你负责端到端结果，对用户负责；
  - 你应主动通过 `sessions_spawn` 找赏金猎人与鉴谎师；
  - 拿到两个结果后，要综合出“推荐等级”与“清晰结论”；
  - 使用文件工具将报告写到固定路径（例如 `~/Desktop/buying_guide.md`）。

- **调用链条（理想行为）**
  1. 用户给 `shop-auditor` 发起需求。
  2. 审计员：
     - `sessions_spawn` 一个 `shop-hunter` 任务（task 中说明要搜哪些平台、返回格式等）；
     - `sessions_spawn` 一个 `shop-skeptic` 任务（基于 A 的输出对卖家逐个评估风险）；
  3. 两个子 Agent 完成后，通过 announce 把各自结果回传到审计员会话；
  4. 审计员整合结果：
     - 计算性价比或推荐分；
     - 生成 Markdown 报告；
     - 使用 `write` / `edit` / `apply_patch` 等工具写文件；
  5. 给用户回复结论与文件路径。

---

## 五、从“同事视角”看三位 Agent（通俗讲解）

### 5.1 谁是谁？

- **OpenClaw Gateway**：像是一家公司总后台 + 总路由器。
  - 所有消息（飞书/Telegram/WhatsApp 等）和所有设备（你的 Mac、浏览器节点）都先到它这里报到。
  - 它决定：这条消息给哪个“同事”（Agent）处理，可以用哪些工具。

- **Agent**：一个“有设定、有记忆、有工具权限的数字同事”。
  - 每个 Agent 有：
    - 自己的“档案夹”（workspace，里面写着它是谁、干啥、注意事项）；
    - 自己的“聊天记录柜”（sessions）；
    - 自己的“权限卡”（Tools：能不能看文件、能不能跑命令、能不能开浏览器）。

- **大模型（LLM）**：真正干脑力活的“AI 大脑”。
  - OpenClaw 把：
    - 当前消息；
    - Agent 的岗位说明书（AGENTS.md）；
    - 可用工具列表；
    - 一部分历史对话；
  - 一股脑儿丢给大模型，让它决定：
    - 先说点什么；
    - 需不需要点工具（比如开浏览器搜价）；
    - 最终给你什么答案。

简单记法：

- Gateway：前台 + 调度中心；
- Agent：不同岗位的 AI 同事；
- LLM：真正动脑的人，只是经常换人（模型可以换）。

### 5.2 三位同事具体是谁？

1. **赏金猎人（shop-hunter）**
   - 特长：开浏览器、逛电商网站、找最低价。
   - 性格：不八卦、不看评论，只记「平台、价格、卖家、链接」。
   - 工具：只给它浏览器相关能力，不让它乱跑命令或碰服务器。

2. **鉴谎师（shop-skeptic）**
   - 特长：全网搜黑料。
   - 性格：多疑，宁愿错杀一千，不可放过一个烂商家。
   - 工具：只给它 Web 搜索/抓网页文字的能力，不给浏览器、命令行权限。

3. **审计员（shop-auditor）**
   - 特长：看财报 + 写报告。
   - 性格：靠谱、能做决策，会给出“结论 + 理由”并落盘成文件。
   - 工具：
     - 能看/写本地文件（生成 Markdown 报告）；
     - 能发起和管理“子任务”（sub-agents），也就是让其他 Agent 帮忙；
     - 本身不能直接开浏览器、不能执行命令，只做 orchestrator + 文书工作。

> 用户只跟 **审计员** 说话，审计员再去协调赏金猎人和鉴谎师。  
> 这和你跟产品经理说需求，产品经理再去联动开发/测试的模式很像。

### 5.3 它们是怎么一起“写”和“干活”的？

1. 你在 `openclaw chat` 或控制台里，选中 Agent：`shop-auditor`，提出需求。
2. 审计员根据 AGENTS.md 知道需要两个帮手，于是用 `sessions_spawn` 各起一个子任务会话：
   - 子任务 A 交给 `shop-hunter`：搜价 + 输出表格；
   - 子任务 B 交给 `shop-skeptic`：查口碑 + 标记风险。
3. 赏金猎人用浏览器工具逛各平台，找到若干最划算的选项，以 JSON 或表格形式返回。
4. 鉴谎师用 Web 搜索工具“扒小作文”，为每个卖家给出风险等级和典型证据。
5. 两个子任务完成后，由 OpenClaw 的 sub-agents 机制把结果“汇报”给审计员的主会话。
6. 审计员综合价格与风险，写出一份 Markdown 报告（含表格 + 结论），写到比如 `~/Desktop/buying_guide.md`，并向你解释推荐哪家、为什么。

“写”的含义：

- 写配置：在 `openclaw.json` 的 `agents.list` 中登记这三位同事是谁、住哪（workspace）、能干啥（tools）、能调谁（subagents）；
- 写岗位说明书：在每个 workspace 下写好 `AGENTS.md`，告诉大模型这个角色的性格、目标与边界。

---

## 六、多 Agent 场景实战：脚本与命令

### 6.1 一键基础配置脚本（必跑）

- 脚本位置：`scripts/multi-agents-setup.sh`
- 主要作用（当前实现）：

  - 在 `~/.openclaw/openclaw.json` 中：
    - 追加/补充 `agents.list` 中的三个 Agent：
      - `shop-hunter` / `shop-skeptic` / `shop-auditor`
    - 为 `shop-auditor` 配置：
      - `subagents.allowAgents = ["shop-hunter", "shop-skeptic"]`  
        允许它用 `sessions_spawn` 调用这两个子 Agent。
  - 在本地创建三个 workspace：
    - `~/.openclaw/workspace-shop-hunter/AGENTS.md`  
    - `~/.openclaw/workspace-shop-skeptic/AGENTS.md`  
    - `~/.openclaw/workspace-shop-auditor/AGENTS.md`  
    - 写好三种人格与职责说明，指导模型分工协作。

> 注意：脚本**不会修改 bindings**，不会影响你现有的通道路由，只是新增三个 Agent 与 workspace。

#### 6.1.1 运行脚本

```bash
cd /Users/zhanlifeng/Documents/workspace/openclaw
bash scripts/multi-agents-setup.sh
```

预期输出要点：

- 打印配置备份路径：`~/.openclaw/openclaw.json.bak-multi-agents-YYYYMMDD-HHMMSS`
- 提示 `[ADD] Agent shop-hunter 已添加。` 等若干行；
- 提示 `[WRITE] 创建 ~/.openclaw/workspace-*/AGENTS.md`。

#### 6.1.2 验证 Agents 是否就绪

```bash
openclaw agents list
```

在输出中应能看到 3 个新 Agent（只要 `id` 对得上即可）：

- `shop-hunter`
- `shop-skeptic`
- `shop-auditor`

如果你已经有同名 Agent，脚本会做“最小补充”，并不会覆盖已有字段。

### 6.2 Chat 侧业务验证步骤（从用户视角）

> 通过 `openclaw chat` 或 Web 控制台的聊天界面来验证**多 Agent 协作业务链条**是否通顺。

#### 6.2.1 将会话指向审计员 Agent

你可以用任意一种方式把当前会话绑定到 `shop-auditor`：

- CLI（如果你的版本支持指定 agent）：

  ```bash
  openclaw chat --agent shop-auditor
  ```

- Web 控制台 / Desktop App：
  - 在新建会话 / 配置面板中，将 `agentId` 选为 `shop-auditor`。

> 如果你的环境还没有明显的 agent 选择入口，可以先在控制台中看一眼 `agents` 区域的 UI，确认 3 个 Agent 是否被识别；后续可以按自己偏好的入口选择 `shop-auditor`。

#### 6.2.2 触发完整业务流程的示例对话

在与 `shop-auditor` 对话中，输入类似指令：

> “我想买一台 Sony WH-1000XM5 黑色款，请按你们的多 Agent 流程来：  
> 1）让赏金猎人在 Amazon 和 eBay 找出 2–3 个最低价选项；  
> 2）让鉴谎师检查这些卖家的口碑和黑历史；  
> 3）你最后生成 Markdown 报告文件（包含表格和结论），保存在我的桌面，并把结论告诉我。”

**预期理想行为（逻辑上）：**

- 审计员会：
  1. 解释自己将调用“赏金猎人”和“鉴谎师”的子任务；
  2. 通过 `sessions_spawn`（子 Agent 机制）分别触发 `shop-hunter` / `shop-skeptic`：
     - `shop-hunter` 使用浏览器工具搜价；
     - `shop-skeptic` 使用 Web 工具查口碑；
  3. 收集两个子 Agent 的结果后，在当前会话中总结成表格并调用文件写入工具，落盘 Markdown。

> 由于我们在 `AGENTS.md` 里已经明确写好角色职责和协作方式，在 Tools / Skills 合理配置的前提下，模型会倾向于按这个分工来调用工具与子 Agent。

#### 6.2.3 文件落地验证

在对话得到“报告已写入桌面”的回复后，你可以在本机终端验证文件存在：

```bash
ls ~/Desktop | grep buying_guide || echo '未找到 buying_guide 文件，请检查 Agent 输出或 workspace 配置路径。'
```

如果你在 `AGENTS.md` 或后续调教中修改了路径，按你自己的路径检查即可。

### 6.3 命令级与状态级验证（从运维视角）

#### 6.3.1 验证配置中的 Agents 列表

> 不依赖 OpenClaw CLI，本地直接读 JSON。

```bash
jq '.agents.list | map(.id)' ~/.openclaw/openclaw.json
```

预期输出应至少包含：

- `"shop-hunter"`
- `"shop-skeptic"`
- `"shop-auditor"`

若机器没有 `jq`，可以用 Python：

```bash
python3 - <<'PY'
import json, os
cfg = json.load(open(os.path.expanduser("~/.openclaw/openclaw.json")))
print([a.get("id") for a in cfg.get("agents", {}).get("list", [])])
PY
```

#### 6.3.2 使用辅助脚本一键检查

> 更省事的做法：直接用项目内的验证脚本完成 6.3.1 + 6.3.3 的大部分检查。

```bash
cd /Users/zhanlifeng/Documents/workspace/openclaw
bash scripts/multi-agents-verify.sh
```

脚本会：

- 列出当前 `agents.list` 中的所有 `id`；
- 检查是否存在 `shop-hunter` / `shop-skeptic` / `shop-auditor`；
- 检查 `shop-auditor.subagents.allowAgents` 是否包含这两个子 Agent；
- 检查三个 Agent 的 workspace 目录和 `AGENTS.md` 是否存在；
- 最后给出下一步操作建议（如何挂到 `shop-auditor` 并触发业务验证）。

#### 6.3.3 验证审计员的 subagents.allowAgents

```bash
jq '.agents.list[] | select(.id=="shop-auditor") | .subagents' ~/.openclaw/openclaw.json
```

预期至少包含：

- `"allowAgents": ["shop-hunter", "shop-skeptic"]`

如果为空或缺失，说明脚本没成功写入，可重新跑一遍或手工修正。

#### 6.3.4 会话与子 Agent 调用痕迹（概念说明）

在实际运行中，当 `shop-auditor` 使用 `sessions_spawn` 调用子 Agent 时，底层会创建新的 session（形如 `agent::subagent:`）。你可以通过：

- 在 Gateway 主机上查看 `~/.openclaw/agents/<agentId>/sessions` 目录中文件数量变化；
- 或在日志中检索包含 `sessions_spawn`、`subagent` 关键字的记录；

来确认子 Agent 确实有被调起。  
（具体 CLI 封装会随版本演进，建议按你当前版本的 `openclaw` 文档查看 session 工具相关命令。）

---

## 七、调度与 Prompt 模板（给审计员与操作者用）

### 7.1 审计员的 System / AGENTS.md 模板片段

以下内容可以直接合并到 `~/.openclaw/workspace-shop-auditor/AGENTS.md` 中，  
或复制到你在 Dashboard 里为 `shop-auditor` 配置的 System Prompt：

```markdown
你是「审计员 (shop-auditor)」，负责协调整个 Smart Shopper 协议：

1. 接收用户的购物需求（商品名称、平台偏好等）。
2. 通过子 Agent 完成两件事：
   - 赏金猎人 (shop-hunter)：负责从各大电商网站上找出若干价格最低的候选项；
   - 鉴谎师   (shop-skeptic)：负责基于候选列表查口碑、挖黑料，并为每个卖家打风险标签。
3. 整合两边结果：
   - 计算一个简单的推荐等级（例如「强烈推荐 / 推荐 / 不建议」），
   - 写出 Markdown 报告（包含表格与结论），
   - 将报告写入本机固定路径（例如 ~/Desktop/buying_guide.md）。

重要规则：

- 你是用户唯一的对话入口。用户只和你说话，你通过子 Agent 完成具体工作。
- 你应该使用 `sessions_spawn` 工具来调用子 Agent，而不是在一个对话里同时扮演三个人。
- 赏金猎人只关心「平台 / 价格 / 卖家 / 链接」，不负责风险判断；
- 鉴谎师只关心「风险与黑料」，不负责价格排序；
- 你自己负责权衡价格与风险，给出最终推荐。

建议的协作模式：

1. 收到用户需求后，用自然语言总结成内部任务说明（备注）。
2. 调用 `sessions_spawn` 向 `shop-hunter` 发起子任务，任务中要求：
   - 最少返回 2 个、最多 5 个候选；
   - 输出结构化 JSON 数组或 Markdown 表；
   - 字段至少包含：平台(source)、价格(price)、卖家(seller)、链接(link)。
3. 等待 hunter 的结果被 announce 回来；
4. 再用 `sessions_spawn` 向 `shop-skeptic` 发起子任务，将 hunter 的输出作为输入：
   - 要求对每个卖家打出「风险等级」(低/中/高)；
   - 列出 1–2 条典型负面评价摘要（若有）；
   - 输出结构化 JSON 列表或 Markdown 表。
5. 最后你自己整合两个表，生成一份 Markdown 报告并写入文件：
   - 报告中包含清晰的表格与「最终推荐结论」；
   - 明确说明「为什么推荐 / 为什么不推荐」。
```

### 7.2 审计员 → 子 Agent 的 task 思路模板

#### 7.2.1 给赏金猎人的 task 风格

```markdown
当你通过 `sessions_spawn` 调用「赏金猎人 (shop-hunter)」时，task 内容应尽量遵循以下结构：

任务目标（示例）：
- 商品：Sony WH-1000XM5 黑色款
- 需要比较的平台：Amazon、eBay（若用户给了具体平台，则遵从用户）

你应在 task 描述中包含：
1. 商品名称与关键属性（如颜色、存储容量等）。
2. 需要搜索的平台列表或优先级。
3. 返回格式要求，例如：

   请以 **JSON 数组** 的形式返回，每个元素包含字段：
   - source: 平台名称（如 "Amazon" / "eBay"）
   - price: 数值（去掉货币符号后的价格，单位为用户当地货币）
   - seller: 卖家名称
   - link: 商品详情链接

4. 对数量的约束：例如「请返回 2–5 个价格最低但看起来可信的选项」。
```

#### 7.2.2 给鉴谎师的 task 风格

```markdown
当你通过 `sessions_spawn` 调用「鉴谎师 (shop-skeptic)」时，task 内容应尽量遵循以下结构：

输入：赏金猎人返回的候选列表（平台 / 价格 / 卖家 / 链接）。

请你：
1. 针对每一个候选卖家，使用 Web 搜索工具检索其口碑，
   可以组合关键词如「卖家名 + scam / review / 假货 / 翻新 / 售后」；
2. 汇总出一个「风险等级」：
   - 绿色（低风险）：几乎没有严重负面评价；
   - 黄色（中风险）：有零星投诉，但问题不致命；
   - 红色（高风险）：有明显的假货/翻新/售后拒保等严重问题。
3. 为每个卖家给出 1–2 条典型负面评价的简短摘要（若没有，可以说明「未发现明显负面」）。

返回格式建议为 **JSON 数组** 或 Markdown 表格，例如：
- seller
- riskLevel ("low" | "medium" | "high")
- reasons（简短文字或列表）
```

### 7.3 最终报告模板

```markdown
在整合赏金猎人和鉴谎师的结果时，请按以下步骤生成报告：

1. 将两个结果按卖家进行「join」，得到包含以下字段的总表：
   - 平台 (source)
   - 价格 (price)
   - 卖家 (seller)
   - 风险等级 (riskLevel)
   - 简要风险理由 (riskSummary)
   - 推荐建议 (recommendation)

2. 对每个候选项生成「推荐建议」字段，例子：
   - 风险高 + 价格再便宜也：写「绝对不要买」；
   - 风险低 + 价格稍高：写「推荐购买」；
   - 其他：写「可以考虑，但需注意 XXX」。

3. 生成 Markdown 报告，结构示例：

   ```markdown
   # 购物决策建议：{商品名称}

   | 平台 | 价格 | 卖家 | 风险等级 | 建议 |
   |------|------|------|----------|------|
   | ...  | ...  | ...  | ...      | ...  |

   **结论**：用自然语言总结 2–3 句话，明确推荐哪一个，为什么。
   ```

4. 使用文件工具将该 Markdown 报告写入固定路径，例如：
   - `~/Desktop/buying_guide.md`

5. 在回复用户时：
   - 告知报告路径；
   - 用简洁自然语言再复述一次结论。
```

### 7.4 面向操作者的推荐起手 Prompt

在 `openclaw chat` 里与 `shop-auditor` 开启一轮演示时，你可以直接用下面这段话作为起手：

> 「接下来请你以 Smart Shopper 多 Agent 模式工作。  
> 你本人作为审计员 (shop-auditor)，只负责接收需求、调度子 Agent 和输出最终报告。  
> 请调用赏金猎人 (shop-hunter) 去在 Amazon 和 eBay 搜索 `Sony WH-1000XM5` 的 2–3 个最低价候选，  
> 再调用鉴谎师 (shop-skeptic) 去检查这些卖家的口碑和黑历史，  
> 最后你生成一个带表格和结论的 Markdown 报告写到 `~/Desktop/buying_guide.md`，  
> 并在这里用一句话告诉我你推荐买哪一家的，为什么。」

这种起手方式，会显式提醒审计员「要用子 Agent 模式来干活」，  
配合我们在 `AGENTS.md` 和本模板里写的约定，大概率能稳定走完整个多 Agent 协作链路。  

---

## 八、设计要点小结

1. **职责单一**：每个 Agent 只做一件事，Prompt 和 tools 权限都围绕这件事。
2. **权限内聚**：高危能力（浏览器、命令、节点）尽量集中在少数 Agent 上，并由一个安全的 orchestrator 统一调度。
3. **workspace 驱动**：通过 `AGENTS.md`（以及可选的 SOUL/USER/Skills），把“岗位说明书”写到文件里，让模型在每次调用前都能读到。
4. **通过 sub-agents 实现协作**：用 `sessions_spawn` 显式表达“起子任务，完成后回来报”的模式，而不是把所有逻辑塞进一个长 Prompt。
5. **配置信息显式化**：所有多 Agent 结构与边界都落在 `openclaw.json` 的 `agents.list` 和相关字段中，运维可直接审查与调整。

这样设计出来的多 Agent 系统，既容易解释（每个 Agent 都有清晰 job description），又便于在生产环境调试、缩放和加防线，同时也为你后续设计更多类似的多 Agent 场景（机票比价、SaaS 方案选型、供应商评估等）提供了一套可以直接复用的“模版工程”。  

