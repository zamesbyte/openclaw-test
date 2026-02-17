# OpenClaw 配置、CLI 与功能总览

> 版本：2026.2.12（基于当前代码与已修复的 CLI 行为整理）

---

## 1. 配置总览（`~/.openclaw/openclaw.json`）

### 1.1 顶层结构大致包括

- `models`：模型提供商与可用模型列表  
- `agents`：默认 Agent 配置（默认模型、并发、memorySearch 等）  
- `hooks`：Webhook（包括 Gmail Webhook）  
- `channels`：通道（飞书、Discord 等）  
- `gateway`：网关监听地址、认证方式  
- `memory`：记忆后端（builtin / qmd）  
- `plugins`：插件开关  
- 其他：`messages`、`commands` 等

**查看/编辑配置：**

```bash
openclaw config print          # 打印完整配置
openclaw config get hooks      # 查看 hooks 段
openclaw config edit           # 在编辑器中打开 openclaw.json
```

> 提示：所有 CLI 默认读取同一份 `~/.openclaw/openclaw.json`，不区分“全局/本地”。

---

## 2. 常用 CLI 命令（配置 / 网关 / Memory）

### 2.1 配置相关

```bash
# 按路径读取字段
openclaw config get memory.backend
openclaw config get agents.defaults.model.primary

# 设置字段
openclaw config set memory.backend builtin
openclaw config set memory.backend qmd
```

### 2.2 配置校验与修复

当前 CLI 启动时会用内置 schema 校验配置；如果配置里有旧版本 CLI 不认识的字段，会报：

```text
Config invalid at ~/.openclaw/openclaw.json: ...
Run: openclaw doctor --fix
```

**一键修复：**

```bash
openclaw doctor --fix
```

作用：

- 删除 schema 不认识的字段（历史上如 `memorySearch.query.rerank` 一类实验字段）；
- 输出一份「干净」的配置，使所有 `openclaw` 子命令恢复正常工作。

之后再执行：

```bash
openclaw config set ...
openclaw memory status
openclaw gateway status
```

都不应再出现全局的 `Config invalid` 报错。

---

## 3. Gateway（网关）相关命令

### 3.1 启停 / 重启 / 状态

```bash
openclaw gateway start      # 启动网关
openclaw gateway stop       # 停止网关
openclaw gateway restart    # 修改关键配置后必须重启
openclaw gateway status     # 查看当前状态与日志位置
```

### 3.2 Dashboard / 控制台访问

- 默认 HTTP 地址：`http://127.0.0.1:18789/`
- 默认 WS 地址：`ws://127.0.0.1:18789`

推荐使用：

```bash
openclaw dashboard
```

该命令会自动生成带正确 `?token=...` 的 URL 并打开浏览器，解决「unauthorized (1008): gateway token mismatch」类错误。

若需手动配置：

```bash
openclaw config get gateway.auth.token
```

把该 token 粘贴到控制台设置中的「Gateway Token」即可。

---

## 4. Memory 后端与切换（builtin / qmd）

详见 `doc/sum/MEMORY机制总览与验证实践.md`，这里只给最常用命令：

```bash
# 查看当前后端与状态
openclaw memory status
openclaw memory status --json | jq -r '.[0].status.backend'

# 切换后端（需重启网关）
openclaw config set memory.backend builtin
openclaw gateway restart

openclaw config set memory.backend qmd
openclaw gateway restart
```

当使用 QMD 且失败时，日志会打印 `qmd memory failed; switching to builtin`，表示已自动回退到 builtin。

---

## 5. 功能全景（概览）

### 5.1 消息通道

支持 30+ 通道（Telegram / WhatsApp / Discord / Slack / iMessage / Signal / Google Chat / MS Teams / 飞书 等），通过插件启用：

```bash
openclaw plugins enable telegram
openclaw channels add --channel telegram --token "BOT_TOKEN"
openclaw channels status
openclaw channels logs
```

飞书通道配置示例（已按当前环境）：

- `channels.feishu.enabled = true`
- `channels.feishu.appId = cli_a91a26d46278dcbd`
- `channels.feishu.dmPolicy = "open"`, `channels.feishu.allowFrom = ["*"]`

### 5.2 Agent 工具与自动化

常见内置工具：

- 文件类：`read` / `write` / `edit`
- 命令类：`exec` / `process`
- Web 类：`web_search` / `web_fetch` / `browser`
- 消息类：`message` / `tts`
- 记忆类：`memory_search` / `memory_get`
- 会话类：`sessions_list` / `sessions_history` / `sessions_send` / `sessions_spawn`
- 自动化：`cron` / `gateway`

工具 profile（很重要）：

```bash
# minimal / messaging / coding / full
openclaw config get tools.profile
```

`full` = 不限制工具使用（当前环境为 full），`coding` / `messaging` 为子集。

### 5.3 浏览器控制（与飞书联动）

浏览器相关细节与踩坑修复见：  
`doc/sum/飞书浏览器控制与工具调用总结.md`

关键点：

- `browser.enabled = true`，`browser.defaultProfile = "openclaw"`；
- 推荐浏览器任务使用 `qwen-max` 以保证 tool calling 稳定；
- 典型命令：

```bash
openclaw browser --browser-profile openclaw start
openclaw browser --browser-profile openclaw open https://example.com
openclaw browser --browser-profile openclaw snapshot
```

### 5.4 Gmail 集成与飞书通知

完整说明见：  
`doc/sum/Gmail集成一站式（Webhook收信通知飞书+发信）.md`

简要回顾：

- 使用 `openclaw webhooks gmail setup` + Gmail Pub/Sub + `gog gmail watch serve`；
- Gmail 新邮件 → `/hooks/gmail` → Agent 总结 → 通过 `hooks.mappings` 发到飞书；
- 当前环境已配置：
  - `hooks.gmail.account = "lifeng.zhan90@gmail.com"`
  - `hooks.mappings[0].channel = "feishu"`
  - `hooks.mappings[0].to = "ou_fc69cb46e0574b061b5cde6c3bf3b159"`

---

## 6. 典型排错路径（CLI / 配置）

1. **所有命令开头都出现 Config invalid**  
   - 运行：`openclaw doctor --fix` 清理未知字段；
   - 再试：`openclaw config get ...` / `openclaw memory status`。
2. **Gateway 无法启动或 Dashboard 503**  
   - `openclaw gateway status` 看日志路径；  
   - 打开当天 `/tmp/openclaw/openclaw-YYYY-MM-DD.log`；
   - 结合 `openclaw doctor --fix` 与 `openclaw gateway restart`。
3. **浏览器相关问题**  
   - 参考：`doc/sum/飞书浏览器控制与工具调用总结.md`。
4. **Gmail 收信无通知**  
   - 参考：`doc/sum/Gmail集成一站式（Webhook收信通知飞书+发信）.md` 的故障排查章节。

