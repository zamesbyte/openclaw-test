# OpenClaw 功能全景总结

> 版本: 2026.2.12 | 平台: macOS
> OpenClaw 是一个自托管的端到端加密 AI 助手网关平台

---

## 一、平台概述

OpenClaw 是一个将 AI 模型（如 Claude、GPT、Qwen 等）连接到各种消息通道（WhatsApp、Telegram、Discord 等）的**自托管网关**。它让你拥有一个统一的 AI 助手，可以跨平台与你交互，同时具备文件操作、命令执行、浏览器控制、定时任务等强大能力。

### 核心架构
```
消息通道 ←→ [WebSocket 网关 (18789)] ←→ AI 模型提供商
                    ↕
            工具 / 技能 / 自动化
                    ↕
            macOS / iOS / Android 应用
```

---

## 二、消息通道（30+ 支持）

### 主流通道

| 通道 | 插件 ID | 说明 |
|------|---------|------|
| **Discord** | `discord` | 支持服务器/DM/群组，斜杠命令，文件附件 |
| **Telegram** | `telegram` | Bot API，支持原生菜单命令、群组、DM |
| **WhatsApp** | `whatsapp` | WhatsApp Web 协议 (Baileys)，QR 扫码链接 |
| **Slack** | `slack` | Bolt 框架，支持频道、DM、App Token |
| **iMessage** | `imessage` | macOS 原生 iMessage 集成 |
| **Signal** | `signal` | 通过 signal-cli，端到端加密 |
| **Google Chat** | `googlechat` | Google Workspace 集成 |
| **Microsoft Teams** | `msteams` | Teams Bot 集成 |
| **飞书/Lark** | `feishu` | 飞书机器人（社区维护） |
| **IRC** | `irc` | IRC 协议 |

### 更多通道

| 通道 | 说明 |
|------|------|
| **Matrix** | 去中心化通信协议 |
| **Mattermost** | 开源 Slack 替代 |
| **Nostr** | 去中心化社交协议 (NIP-04 加密 DM) |
| **BlueBubbles** | iMessage 替代（推荐） |
| **LINE** | LINE 消息平台 |
| **Zalo** | 越南 Zalo 平台 |
| **Tlon/Urbit** | Urbit 网络 |
| **Twitch** | 直播平台 |
| **Nextcloud Talk** | Nextcloud 通讯 |
| **WebChat** | 内置 Web 聊天界面 |

### 使用方式
```bash
# 启用通道
openclaw plugins enable telegram
openclaw channels add --channel telegram --token "BOT_TOKEN"

# 查看状态
openclaw channels status

# 查看通道日志
openclaw channels logs
```

---

## 三、AI 模型支持

### 支持的提供商

| 提供商 | 协议 | 说明 |
|--------|------|------|
| **Anthropic** | 原生 | Claude 系列 (Claude 4, Sonnet, Haiku) |
| **OpenAI** | 原生 | GPT-4o, GPT-4, o1/o3 系列 |
| **Google Gemini** | 原生 | Gemini Pro/Flash 系列 |
| **GitHub Copilot** | OAuth | 通过 GitHub 设备流登录 |
| **OpenRouter** | OpenAI 兼容 | 聚合 100+ 模型 |
| **阿里云 DashScope** | OpenAI 兼容 | 通义千问系列 |
| **自定义端点** | OpenAI 兼容 | 任何 OpenAI 兼容 API |
| **本地模型** | node-llama-cpp | 本地 LLM 推理 |

### 模型功能
- **模型别名**: 为模型设置短名称
- **回退列表**: 主模型不可用时自动切换
- **图像模型**: 独立配置图像生成/分析模型
- **多 Auth Profile**: 同一提供商多个 API Key 轮换
- **Thinking 级别**: off / minimal / low / medium / high

### 使用方式
```bash
openclaw models status           # 查看模型状态
openclaw models set <model>      # 设置默认模型
openclaw models fallbacks set a b c  # 设置回退链
openclaw models auth add         # 添加认证
```

---

## 四、Agent 工具体系

### 文件系统工具

| 工具 | 功能 |
|------|------|
| `read` | 读取工作区文件 |
| `write` | 写入文件 |
| `edit` | 原地编辑文件 |
| `apply_patch` | 批量结构化补丁（实验性） |

### 命令执行

| 工具 | 功能 |
|------|------|
| `exec` | 执行 shell 命令（支持沙盒/网关/节点宿主） |
| `process` | 管理后台进程（列出/轮询/写入/终止） |

### Web 工具

| 工具 | 功能 |
|------|------|
| `web_search` | 网络搜索（Brave/Perplexity/Grok API） |
| `web_fetch` | 抓取网页内容（HTML→Markdown 转换） |
| `browser` | 完整浏览器控制（见下文） |

### 通信工具

| 工具 | 功能 |
|------|------|
| `message` | 跨通道发送消息（支持所有已配置通道） |
| `tts` | 文本转语音 |

### 会话管理

| 工具 | 功能 |
|------|------|
| `sessions_list` | 列出所有会话 |
| `sessions_history` | 查看会话历史 |
| `sessions_send` | 向其他会话发送消息 |
| `sessions_spawn` | 启动子 Agent |
| `session_status` | 会话状态 |
| `agents_list` | 列出 Agent ID |

### 自动化工具

| 工具 | 功能 |
|------|------|
| `cron` | 定时任务管理 |
| `gateway` | 网关控制（重启/配置更新） |

### 记忆工具

| 工具 | 功能 |
|------|------|
| `memory_search` | 语义搜索记忆文件 |
| `memory_get` | 读取特定记忆文件 |

### 节点工具

| 工具 | 功能 |
|------|------|
| `nodes` | 节点发现、配对、通知、摄像头、录屏、定位 |
| `canvas` | 可视化画布控制 |
| `image` | 图像分析 |

### 工具配置
```bash
# 工具预设
# minimal: 仅 session_status
# coding: 文件 + 运行时 + 会话 + 记忆
# messaging: 消息 + 会话
# full: 无限制（默认）

# 通过对话配置: 告诉 Bot "禁用 exec 工具"
```

---

## 五、浏览器控制

OpenClaw 内置完整的浏览器自动化能力。

### 功能

| 操作 | 说明 |
|------|------|
| `status` | 浏览器状态 |
| `start/stop` | 启停浏览器 |
| `open` | 打开 URL |
| `tabs` | 列出标签页 |
| `focus/close` | 聚焦/关闭标签 |
| `snapshot` | DOM 快照（用于 AI 理解页面） |
| `screenshot` | 页面截图 |
| `act` | 点击、输入、按键、悬停、拖拽、选择、填充、等待 |
| `navigate` | 前进/后退/刷新 |
| `console` | 执行 JavaScript |
| `pdf` | 导出 PDF |
| `upload` | 上传文件 |
| `dialog` | 处理弹窗 |

### 使用场景
- 自动填写表单
- 网页数据抓取
- 自动化测试
- 在线操作代理

```bash
# 启动浏览器
openclaw browser start

# 通过对话使用: "帮我打开百度搜索今天的天气"
```

---

## 六、Canvas 与 A2UI

### Canvas
- macOS 应用中的 Agent 可控面板（WKWebView）
- Agent 可以展示自定义 UI、图表、交互界面
- 支持 HTML/CSS/JS 渲染

### A2UI (Agent-to-UI)
- Agent 驱动的可视化工作空间
- 支持实时更新、数据模型推送
- 丰富的交互组件

### 使用场景
- 数据可视化展示
- 交互式表单
- 实时仪表板
- 自定义工具界面

---

## 七、语音功能

### Talk Mode（语音对话）
- 连续语音循环：监听 → 转录 → 模型 → TTS 回放
- 支持中断（说话即打断）
- ElevenTTS 流式合成

### Voice Wake（语音唤醒）
- macOS 应用支持语音唤醒词
- 免触摸启动对话

### TTS 提供商
| 提供商 | 说明 |
|--------|------|
| ElevenLabs | 最自然的语音，需要 API Key |
| OpenAI TTS | OpenAI 语音合成 |
| Edge TTS | 免费，微软 Edge 语音（默认） |

### 使用方式
- macOS 应用菜单栏 → Talk Mode
- iOS/Android 应用中开启 Talk Mode

---

## 八、节点系统 (Nodes)

节点是连接到网关的设备，提供物理世界交互能力。

### 节点类型
| 节点 | 平台 | 功能 |
|------|------|------|
| macOS App | macOS | Canvas、摄像头、录屏、语音唤醒、Talk |
| iOS App | iOS | Canvas、摄像头、录屏、位置、Talk |
| Android App | Android | Canvas、摄像头、录屏、位置、Talk、短信 |

### 节点能力

| 能力 | 说明 |
|------|------|
| **摄像头** | 拍照 (`camera_snap`)、录像 (`camera_clip`) |
| **录屏** | 屏幕录制 (`screen_record`) |
| **位置** | 获取 GPS 位置 (`location_get`) |
| **通知** | 推送通知到设备 |
| **系统命令** | 远程执行节点命令 |
| **短信** | Android 发送短信 |

---

## 九、自动化

### 定时任务 (Cron)
```
调度类型:
- at: 一次性定时（ISO 时间戳）
- every: 固定间隔（毫秒）
- cron: 标准 cron 表达式（支持时区）

使用方式:
- 对 Bot 说: "每天早上9点给我发天气预报"
- 命令行: openclaw cron list / openclaw cron add
```

### Webhook
```
端点:
- POST /hooks/wake    - 触发系统事件
- POST /hooks/agent   - 运行独立 Agent 回合
- POST /hooks/<name>  - 自定义映射

认证: Bearer token 或 x-openclaw-token header
```

### Hooks（事件钩子）
```
内置 Hook:
- session-memory: 会话重置时保存记忆
- command-logger: 记录命令到日志
- boot-md: 网关启动时执行 BOOT.md

自定义 Hook 位置:
- 工作区: <workspace>/hooks/
- 共享: ~/.openclaw/hooks/
```

---

## 十、记忆系统

### 工作方式
- **每日记忆**: `memory/YYYY-MM-DD.md` 自动生成
- **长期记忆**: `MEMORY.md` 持久存储
- **语义搜索**: 基于向量的记忆检索

### 向量搜索提供商
| 提供商 | 说明 |
|--------|------|
| OpenAI Embeddings | 需要 API Key |
| Gemini Embeddings | Google 嵌入 |
| Voyage | Voyage AI 嵌入 |
| Local (node-llama-cpp) | 本地向量化 |
| LanceDB | 高级向量数据库 |

### 使用场景
- "你记得我上周说过什么吗？"
- "搜索我们之前讨论的项目方案"
- Agent 自动回忆上下文

---

## 十一、多 Agent 系统

### 路由规则
- 多个 Agent 可同时运行，各有独立工作区、配置和会话
- 按通道、账户、对话方、群组 ID 路由到不同 Agent
- 最精确匹配优先

### 使用场景
| Agent | 用途 |
|-------|------|
| main (默认) | 个人助手 |
| work | 工作专用，只在 Slack 频道 |
| family | 家庭群组，限制工具权限 |
| public | 公开 Bot，完全沙盒化 |

### Agent 间通信
- Agent 之间可通过 `sessions_send` 互相发消息
- `sessions_spawn` 启动子 Agent 执行任务

---

## 十二、安全体系

### DM 安全
| 策略 | 说明 |
|------|------|
| `pairing` | 默认。陌生人收到配对码，需批准后才能交互 |
| `allowlist` | 仅允许列表中的用户 |
| `open` | 允许所有人（不推荐） |
| `disabled` | 禁用 DM |

### 沙盒隔离
- Docker 容器化工具执行
- 每 Agent / 每会话隔离
- 可配置网络、内存、CPU 限制
- 文件系统只读选项

### 其他安全功能
- Gateway Token 认证
- 设备配对
- 执行审批（敏感命令需确认）
- 安全审计: `openclaw security audit --deep`

---

## 十三、macOS 应用功能

| 功能 | 说明 |
|------|------|
| **菜单栏应用** | 常驻系统栏，快速访问 |
| **WebChat** | 内嵌 Web 聊天界面 |
| **Control UI** | 控制面板 |
| **Canvas 面板** | Agent 可控可视化面板 |
| **Talk Mode** | 语音对话覆盖层 |
| **Voice Wake** | 语音唤醒 |
| **节点模式** | 连接为网关节点，提供摄像头/录屏等 |
| **Exec 审批** | 设置敏感命令审批策略 |
| **技能管理** | UI 安装/启用/禁用技能 |

---

## 十四、技能生态

### 内置技能
| 技能 | 说明 |
|------|------|
| `healthcheck` | 系统健康检查 |
| `skill-creator` | 帮助创建新技能 |
| `weather` | 天气查询 |

### ClawHub 技能市场
- 社区贡献的技能库
- `clawhub install <skill-name>`
- `clawhub update`

### 自定义技能
- 工作区 `skills/` 目录放置自定义技能
- 支持 Markdown + JSON Schema 定义
- 支持 Python、Node.js、Shell 执行

---

## 十五、Pi Agent / 编码 Agent

### 功能
- 嵌入式编码 Agent，深度集成
- 支持工作区文件操作
- 支持终端命令执行
- TUI（终端 UI）模式

### 使用方式
```bash
# 交互式 TUI
openclaw tui

# 命令行 Agent
openclaw agent --local --session-id coding --message "帮我写一个 Python 脚本"
```

---

## 十六、CLI 命令速查

### 核心命令
```bash
openclaw status              # 完整状态
openclaw doctor              # 健康诊断
openclaw gateway start/stop  # 网关管理
openclaw dashboard           # 打开控制面板
openclaw logs --follow       # 实时日志
```

### 配置管理
```bash
openclaw configure           # 交互式配置
openclaw config get <path>   # 读取配置
openclaw config set <path>   # 设置配置
openclaw models status       # 模型状态
openclaw channels status     # 通道状态
```

### 会话与交互
```bash
openclaw agent --local -m "消息"  # 本地 Agent
openclaw tui                     # 终端 UI
openclaw sessions list           # 会话列表
openclaw message send ...        # 发送消息
```

### 维护
```bash
openclaw update              # 更新
openclaw plugins list        # 插件列表
openclaw security audit      # 安全审计
openclaw reset               # 重置
```

---

## 十七、典型使用场景

| 场景 | 实现方式 |
|------|----------|
| **个人 AI 助手** | Discord/Telegram Bot + 模型配置 |
| **跨平台统一助手** | 多通道配置，同一 Agent 响应所有平台 |
| **家庭智能管家** | 多 Agent 路由，家庭群组独立 Agent |
| **自动化运维** | Cron + Webhook + exec 工具 |
| **代码助手** | Pi Agent + 文件/命令工具 |
| **网页自动化** | Browser 工具 + 自动填表/抓取 |
| **定时提醒/汇报** | Cron 定时 + message 投递 |
| **知识管理** | Memory 系统 + 语义搜索 |
| **远程设备控制** | Node 系统 + 摄像头/位置/通知 |
| **内容创作** | AI 生成 + Canvas 展示 |
| **安全团队助手** | 沙盒化 + 执行审批 + 安全审计 |

---

## 十八、数据目录结构

```
~/.openclaw/
├── openclaw.json           # 主配置文件
├── agents/
│   └── main/
│       ├── agent/           # Agent 配置和认证
│       └── sessions/        # 会话数据
├── credentials/             # OAuth/Token 凭据
├── workspace/               # 工作区（AGENTS.md, SOUL.md 等）
├── skills/                  # 共享技能
├── hooks/                   # 共享钩子
├── logs/                    # 日志
├── cron/                    # 定时任务数据
└── memory/                  # 记忆文件
```

---

## 十九、相关资源

| 资源 | 地址 |
|------|------|
| 官方文档 | https://docs.openclaw.ai |
| GitHub 仓库 | https://github.com/openclaw/openclaw |
| ClawHub 技能市场 | https://clawhub.com |
| Discord 社区 | 见官方文档 |
| Dashboard | http://127.0.0.1:18789/ (本地) |
