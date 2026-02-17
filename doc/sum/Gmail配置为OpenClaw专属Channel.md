# Gmail 配置为 OpenClaw 专属 Channel（安装、验证、总结）

> 目标：通过 Gmail 与 AI 对话 —— 你发邮件给 AI，AI 回复你。  
> 技术类型：OpenClaw Hooks（`hooks.gmail`），不是 `channels.whatsapp` 式 Channel，但作用等同「耳朵 + 嘴巴」。  
> 更新日期：2026-02-17

---

## 快速开始（已有依赖时）

若已安装 `gcloud`、`gog`、`tailscale` 并完成登录，可直接执行：

```bash
openclaw webhooks gmail setup --account 你的Gmail地址@gmail.com
openclaw gateway restart
```

然后向该 Gmail 发一封测试邮件，等待 AI 回复。

---

## 一、整体架构

```
Gmail 收件箱
     │
     │ 新邮件
     ▼
Gmail API Watch → Google Cloud Pub/Sub 推送
     │
     ▼
gog gmail watch serve（本地接收推送）
     │
     │ POST /hooks/gmail（含邮件内容）
     ▼
OpenClaw Gateway 的 Hooks 路由
     │
     │ 触发 Agent（将邮件视为 Prompt）
     ▼
LLM 生成回复
     │
     │ 通过 gog gmail send 回信
     ▼
Gmail 发件箱（回复给发件人）
```

**作用**：Gmail 成为 OpenClaw 的「耳朵」（收邮件 = 用户 Prompt）和「嘴巴」（回复邮件 = AI 回复）。

---

## 二、前置依赖

| 依赖 | 用途 | macOS 安装 |
|------|------|-----------|
| **gcloud** | Google Cloud CLI，用于 Pub/Sub 与 Gmail API | `brew install --cask google-cloud-sdk` |
| **gog** (gogcli) | Gmail/Google API CLI，收信、发信、watch | `brew install steipete/tap/gogcli` |
| **tailscale** | 公网暴露推送端点，供 Gmail Pub/Sub 回调 | `brew install tailscale` |
| **OpenClaw** | 已安装，且 Gateway 可访问 | 使用你当前的 `openclaw` |

**macOS 一键安装依赖**：

```bash
brew install --cask google-cloud-sdk
brew install steipete/tap/gogcli
brew install tailscale
```

---

## 三、安装步骤（按顺序）

### 3.1 安装并登录 gcloud

```bash
# 若未安装
brew install --cask google-cloud-sdk

# 登录
gcloud auth login

# 选择/创建 GCP 项目（必须与 gog 使用的 OAuth 客户端同项目）
gcloud config set project <your-project-id>
```

### 3.2 安装并授权 gog

```bash
# 安装
brew install steipete/tap/gogcli

# 首次授权：需准备 OAuth 客户端 JSON（见下方「OAuth 客户端」）
gog auth credentials ~/.config/gogcli/credentials-auth2app.json   # 或你的凭据文件路径
gog auth add 你的Gmail@gmail.com --services gmail                 # 会打开浏览器完成 OAuth

# 验证
gog auth list
```

**OAuth 客户端**：

1. 打开 [Google Cloud Console](https://console.cloud.google.com/) → API 和服务 → 凭据
2. 创建凭据 → OAuth 客户端 ID
3. 应用类型选「桌面应用」，名称可填 `auth2app`
4. 下载 JSON 或手动创建凭据文件（见下方 auth2app 示例）

**auth2app 凭据文件示例**（`~/.config/gogcli/credentials-auth2app.json`）：

```json
{
  "installed": {
    "client_id": "764663573066-asvob261kcp62o9kerthl9ti1se3rq92.apps.googleusercontent.com",
    "client_secret": "<从 Google Cloud 凭据页获取>",
    "auth_uri": "https://accounts.google.com/o/oauth2/auth",
    "token_uri": "https://oauth2.googleapis.com/token",
    "redirect_uris": ["http://localhost"]
  }
}
```

> 安全提醒：`client_secret` 请勿提交到代码库。配置完成后可在 Google Cloud Console 重新生成密钥。

### 3.3 启用 GCP API（若 setup 未自动启用）

```bash
gcloud services enable gmail.googleapis.com pubsub.googleapis.com --project <project-id>
```

### 3.4 安装 Tailscale（用于 Pub/Sub 推送公网可达）

```bash
brew install tailscale

# 登录（需 Tailscale 账号）
tailscale up
```

### 3.5 运行 OpenClaw Gmail 配置向导（推荐）

**运行前请确保 Tailscale 已启动**（例如打开 Tailscale 应用或执行 `tailscale up`），否则会报 `failed to connect to local Tailscale service`。

在完成 gcloud、gog、tailscale 安装和登录后，执行：

```bash
openclaw webhooks gmail setup --account you@gmail.com
```

**说明**：

- `--account`：要监听的 Gmail 地址（必须与 `gog auth add` 中的一致）
- 向导会自动：
  - 创建 Pub/Sub Topic 和 Subscription
  - 配置 Gmail Watch
  - 写入 `~/.openclaw/openclaw.json` 的 `hooks.gmail` 配置
  - 启用 Gmail preset（`hooks.presets: ["gmail"]`）
  - 若使用 Tailscale Funnel，会设置公网推送端点

**可选参数示例**：

```bash
openclaw webhooks gmail setup \
  --account openclaw@gmail.com \
  --project your-gcp-project-id \
  --tailscale funnel \
  --label INBOX
```

### 3.6 确保 Hooks 已启用

检查 `~/.openclaw/openclaw.json` 中：

```json
{
  "hooks": {
    "enabled": true,
    "token": "<hook-token>",
    "path": "/hooks",
    "presets": ["gmail"],
    "gmail": {
      "account": "you@gmail.com",
      "topic": "projects/<project-id>/topics/gog-gmail-watch",
      "subscription": "gog-gmail-watch-push",
      "pushToken": "<push-token>",
      "hookUrl": "http://127.0.0.1:18789/hooks/gmail",
      "includeBody": true,
      "maxBytes": 20000,
      "renewEveryMinutes": 720,
      "serve": { "bind": "127.0.0.1", "port": 8788, "path": "/" },
      "tailscale": { "mode": "funnel", "path": "/gmail-pubsub" }
    }
  }
}
```

若 `hooks.enabled` 为 `false`，请设为 `true` 并重启 Gateway。

---

## 四、启动与运行

### 4.1 Gateway 自动启动 Gmail Watcher（推荐）

当 `hooks.enabled=true` 且 `hooks.gmail.account` 已配置时，Gateway 启动时会自动运行 `gog gmail watch serve`，无需单独启动。

```bash
openclaw gateway restart
```

### 4.2 手动运行 Gmail 服务（可选）

若希望单独跑 Gmail 推送服务（例如 Gateway 与 Gmail 分离部署）：

```bash
openclaw webhooks gmail run
```

**注意**：Gateway 已自动启动 Gmail watcher 时，不要同时运行 `webhooks gmail run`，否则端口 8788 会冲突。

---

## 五、验证

**官方 Webhook 专用**：若仅需「配置步骤 + 验证方法 + 如何检查结果」的精简版，请直接使用 [Gmail官方Webhook集成与验证.md](./Gmail官方Webhook集成与验证.md)，并可运行 `doc/sum/scripts/verify-gmail-webhook.sh` 发送测试邮件并查看检查提示。

### 5.1 发送测试邮件

从**任意邮箱**给 `you@gmail.com`（即 `hooks.gmail.account`）发一封邮件，例如：

- 主题：`OpenClaw 测试`
- 正文：`你好，请用一句话回复我当前时间。`

### 5.2 预期行为

1. Gmail 收到邮件
2. Gmail API 触发 Watch，向 Pub/Sub 推送
3. `gog gmail watch serve` 收到推送，拉取新邮件
4. 向 OpenClaw `http://127.0.0.1:18789/hooks/gmail` 发送 POST
5. OpenClaw 的 Agent 将邮件内容作为 Prompt 运行
6. Agent 调用 `gog gmail send` 回复发件人
7. 发件人收到 AI 的回复邮件

### 5.3 检查命令

```bash
# 查看 Gmail watch 状态
gog gmail watch status --account you@gmail.com

# 查看 Gateway 日志（含 gmail-watcher）
openclaw logs --max-bytes 50000 | grep -i gmail

# 确认 hooks 配置
openclaw config get hooks.gmail.account
openclaw config get hooks.gmail.hookUrl
```

### 5.4 从飞书等渠道让 Agent 发邮件到 Gmail（gmail_send 工具）

当用户从**飞书、Telegram 等**渠道说「把某某内容发到我的 Google 邮箱」时，Agent 需要使用 **`gmail_send`** 工具才能真正发信；仅用 `message` 工具只会把内容发回聊天，不会发邮件。

- **前提**：已配置 `hooks.gmail.account`（与 Gmail Watch 同账号即可），且本机 gog 已对该账号做 `gog auth add ... --services gmail`。
- **操作**：确保配置中有 `hooks.gmail.account` 后重启 Gateway，Agent 即可在任意会话中调用 `gmail_send` 将内容发到指定 Gmail。
- **故障与排查**：参见 [飞书发邮件到 Gmail 故障修复](./飞书发邮件到Gmail故障修复.md)。

### 5.4.1 Agent 读取 Gmail（gmail_list 工具）

当用户说「读一下我的 Gmail」「看看收件箱最近几封邮件」时，Agent 可调用 **`gmail_list`** 工具读取配置账号（`hooks.gmail.account`）的邮件。

- **参数**：`query`（可选，默认 `in:inbox`，支持 Gmail 搜索语法如 `from:xx@example.com`、`newer_than:7d`）、`max`（可选，默认 10，最多 50）。
- **返回**：`ok`、`account`、`query`、`count`、`messages`（每项含 `from`、`subject`、`date`、`snippet`/`body`、`id`）。
- **前提**：与 `gmail_send` 相同（gog 已安装并授权，`hooks.gmail.account` 已配置）。若使用全局安装的 openclaw，需确保安装的版本包含 `gmail_list`（从 openclaw-src 打包安装见 [OpenClaw 前后端打包安装步骤](./OpenClaw前后端打包安装步骤.md)）；若 Agent 仍提示「gmail_list 不存在」，多为当前运行的 CLI/Gateway 来自未含该工具的旧包，需重新打包并全局安装后重试。

### 5.5 CLI 能力验证：读邮件、总结、发新邮件

在 **Gmail API 已启用** 且 **gog 已授权** 的前提下，可用以下步骤验证「读最近 2 封邮件 → 总结 → 发一封新邮件到 Gmail」：

**1. 启用 Gmail API（若未启用）**

- 打开 [Gmail API 启用页](https://console.developers.google.com/apis/api/gmail.googleapis.com/overview?project=764663573066)（将 `project=764663573066` 换成你的项目 ID 或项目编号），点击「启用」。

**2. 读取最近 2 封邮件**

```bash
export GOG_ACCOUNT=lifeng.zhan90@gmail.com   # 换成你的 Gmail
gog gmail messages search "in:inbox" --max 2 --include-body --json --no-input
```

**3. 用 OpenClaw Agent 总结并生成邮件正文**

将上一步 JSON 中每封邮件的 `subject`、`from`、`snippet` 或 body 整理成一段文字，然后：

```bash
openclaw agent --agent main --local --message "下面是我 Gmail 收件箱最近 2 封邮件的摘要（每封一行：发件人 / 主题 / 摘要）：\n\n【这里粘贴步骤 2 的输出或摘要】\n\n请用 2–3 句话总结这两封邮件的要点，并写成一封简短的邮件正文（纯文字，不要称呼和落款），用于发到我的 Gmail 做验证。"
```

把 Agent 返回的正文复制下来，用于步骤 4。

**4. 发送验证邮件到 Gmail**

```bash
gog gmail send --to lifeng.zhan90@gmail.com \
  --subject "OpenClaw 验证：最近 2 封邮件总结" \
  --body "（此处粘贴步骤 3 的正文）" \
  --no-input -y
```

**一键脚本（需先启用 Gmail API 并安装 jq）**

项目内已提供脚本 `doc/sum/scripts/verify-gmail-cli.sh`，会依次执行：读最近 2 封 → 调用 Agent 总结 → 发一封总结邮件到指定 Gmail。执行前请：1）在 GCP 启用 Gmail API；2）设置 `GOG_ACCOUNT`；3）本机已安装 `jq`（`brew install jq`）。

```bash
export GOG_ACCOUNT=lifeng.zhan90@gmail.com
bash doc/sum/scripts/verify-gmail-cli.sh
```

### 5.6 常见问题

| 现象 | 可能原因 | 处理 |
|------|----------|------|
| **Access blocked: auth2app has not completed the Google verification process**（403 access_denied） | OAuth 应用处于「测试」模式，仅测试用户可登录 | 在 [Google Cloud Console](https://console.cloud.google.com/) → API 和服务 → **OAuth 同意屏幕** → 下方 **测试用户** → **添加用户**，填入你的 Gmail（如 `lifeng.zhan90@gmail.com`）→ 保存。保存后重新执行 `gog auth add ...` 并在浏览器中再次授权。 |
| **403 accessNotConfigured: Gmail API has not been used... or it is disabled** | 当前 GCP 项目未启用 Gmail API | 打开 [启用 Gmail API](https://console.developers.google.com/apis/api/gmail.googleapis.com/overview?project=764663573066)（或 Console → 选择与 OAuth 客户端相同的项目 → API 和服务 → 库 → 搜索「Gmail API」→ 启用），等待几分钟后重试。 |
| 收不到回复 | Pub/Sub 推送未到达本机 | 确认 Tailscale 已 `tailscale up`，且 Funnel 已启用 |
| `gog binary not found` | gog 未安装或不在 PATH | `brew install steipete/tap/gogcli`，`which gog` |
| `Invalid topicName` | Pub/Sub Topic 与 OAuth 项目不一致 | 确保 Topic 所在 GCP 项目 = gog OAuth 客户端所在项目 |
| `address already in use` | 8788 端口被占 | 停止重复的 `webhooks gmail run`，或关闭 Gateway 自启的 gmail-watcher 后单独跑 |
| 回复发到错误对象 | mapping 中 `channel`/`to` 未配置 | 默认 `channel: "last"` 会回退到上次路由；若要固定回邮件，由 gog 根据原邮件 `reply-to` 自动回复，一般不需改 |

---

## 六、配置摘要（供速查）

| 配置路径 | 含义 |
|----------|------|
| `hooks.enabled` | 是否启用 Hooks |
| `hooks.token` | OpenClaw 调用 `/hooks/*` 时需携带的 token |
| `hooks.presets` | 包含 `"gmail"` 时启用 Gmail 预设 mapping |
| `hooks.gmail.account` | 监听的 Gmail 地址 |
| `hooks.gmail.topic` | Pub/Sub Topic 全路径 |
| `hooks.gmail.subscription` | Pub/Sub 推送订阅名 |
| `hooks.gmail.pushToken` | Pub/Sub 推送请求的校验 token |
| `hooks.gmail.hookUrl` | OpenClaw 接收推送的 URL（`/hooks/gmail`） |
| `hooks.gmail.model` | （可选）Gmail Hook 专用模型 |
| `hooks.gmail.thinking` | （可选）Gmail Hook 的 thinking 级别 |

---

## 七、总结

- **Gmail 在 OpenClaw 中**：通过 Hooks 实现「邮件即 Prompt、回复即邮件」，功能上等同于专属 Channel。
- **核心依赖**：gcloud、gog、Tailscale；OAuth 客户端需与 Pub/Sub 同 GCP 项目。
- **推荐流程**：安装依赖 → `gog auth` → `openclaw webhooks gmail setup --account you@gmail.com` → 重启 Gateway → 发测试邮件验证。
- **Gateway 集成**：配置好 `hooks.gmail` 后，Gateway 会在启动时自动运行 `gog gmail watch serve`，一般无需手动执行 `webhooks gmail run`。

---

## 八、安装执行记录（2026-02-17）

### 8.1 已完成的步骤

| 步骤 | 命令/操作 | 结果 |
|------|-----------|------|
| 1 | `brew install --cask google-cloud-sdk` | gcloud 556.0.0 已安装 |
| 2 | `brew install steipete/tap/gogcli` | gog 0.11.0 已安装 |
| 3 | `brew install tailscale` | tailscale 1.94.1 已安装 |
| 4 | gcloud 登录 | 已完成 |
| 5 | OAuth 凭据 auth2app | 已创建 `~/.config/gogcli/credentials-auth2app.json` |
| 6 | `gog auth credentials ~/.config/gogcli/credentials-auth2app.json` | 凭据已写入 gog 存储路径 |
| 7 | `gog auth add openclaw@gmail.com --services gmail` | 已启动，**需在浏览器完成 OAuth 授权** |

### 8.2 需要你手动完成的步骤

1. **gog OAuth 授权（进行中）**
   - `gog auth add` 已启动并打开浏览器
   - 若浏览器未打开，可复制终端输出的授权 URL 手动访问
   - 使用你的 Gmail 账号登录，同意 Gmail 权限
   - 完成授权后，gog 会收到回调并存储 refresh token

2. **Tailscale 登录**（若使用 Funnel 推送）
   ```bash
   tailscale up
   ```

3. **运行 OpenClaw Gmail 配置向导**（gog 授权完成后）
   ```bash
   export CLOUDSDK_PYTHON=/opt/homebrew/opt/python@3.13/bin/python3.13
   export PATH="/opt/homebrew/share/google-cloud-sdk/bin:$PATH"
   openclaw webhooks gmail setup --account 你的Gmail@gmail.com
   openclaw gateway restart
   ```

4. **验证**：向 `hooks.gmail.account` 发送测试邮件，确认能收到 AI 回复

### 8.3 环境说明（本机）

- **gcloud**：需设置 `CLOUDSDK_PYTHON` 指向 Python 3.10–3.14，否则会报 Python 3.9 不支持：
  ```bash
  export CLOUDSDK_PYTHON=/opt/homebrew/opt/python@3.13/bin/python3.13
  ```
- **gcloud 路径**：`/opt/homebrew/share/google-cloud-sdk/bin`，可加入 PATH
- **gog 路径**：`/opt/homebrew/bin/gog`
- **OAuth 凭据**：auth2app 桌面应用，客户端 ID `764663573066-asvob261kcp62o9kerthl9ti1se3rq92.apps.googleusercontent.com`

---

## 九、相关文档

| 文档 | 路径 |
|------|------|
| **飞书发邮件到 Gmail 故障修复** | `doc/sum/飞书发邮件到Gmail故障修复.md` |
| Gmail Pub/Sub 官方说明 | `openclaw-src/docs/automation/gmail-pubsub.md` |
| Webhooks 总览 | `openclaw-src/docs/automation/webhook.md` |
| gog 技能说明 | `openclaw-src/skills/gog/SKILL.md` |
| 配置参考 | `openclaw-src/docs/gateway/configuration-reference.md`（搜索 Gmail integration） |
