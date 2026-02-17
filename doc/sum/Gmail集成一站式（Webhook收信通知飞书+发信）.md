# Gmail 集成一站式（Webhook 收信通知飞书 + 发信）

> 目标：
> - **收信触发**：Gmail 收到新邮件 → OpenClaw Hook → **飞书通知你**
> - **可选发信**：在飞书里让 Agent 把内容**发到指定 Gmail**（`gmail_send`）
>
> 官方参考：[Gmail PubSub](https://docs.openclaw.ai/automation/gmail-pubsub)
> 更新日期：2026-02-17

---

## 0. 快速开始（最常用）

### 0.1 收信→飞书通知（推荐）

1. 配置 Gmail Webhook（优先 Tailscale；不行就 cloudflared）  
2. 配置 `hooks.mappings`：`channel: "feishu"` + `to: "<你的 open_id>"`
3. 发送一封测试邮件，看飞书是否收到通知

一键验证脚本（会发测试邮件 + 查日志）：

```bash
OPENCLAW_CLI="node openclaw-src/dist/index.js" doc/sum/scripts/verify-gmail-webhook-feishu.sh
```

---

## 1. 架构（收信触发）

```
Gmail 收件箱
  │ 新邮件
  ▼
Gmail API Watch → Google Cloud Pub/Sub Push
  ▼
本机 gog gmail watch serve（监听 127.0.0.1:8788/<path>）
  ▼
POST http://127.0.0.1:18789/hooks/gmail（带 hooks.token）
  ▼
OpenClaw Gateway → hooks.mappings → 运行 Agent
  ▼
deliver=true → 发到飞书（channel=feishu, to=open_id/chat_id）
```

---

## 2. 前置条件

| 依赖 | 用途 | 检查 |
|------|------|------|
| **gcloud** | Pub/Sub / Gmail API | `gcloud auth list` |
| **gog (gogcli)** | Gmail watch / send / history | `gog auth list` |
| **OpenClaw Gateway** | 接收 `/hooks/gmail` | `openclaw gateway status` |
| **公网入口（二选一）** | Pub/Sub push 到你本机 | **Tailscale Funnel** 或 **cloudflared** |

---

## 3. 配置 Gmail Webhook（收信触发）

### 3.1 方案 A：Tailscale Funnel（官方推荐）

```bash
tailscale status
openclaw webhooks gmail setup --account 你的Gmail@gmail.com
openclaw gateway restart
```

### 3.2 方案 B：cloudflared（无法使用 Tailscale 的备选）

> 适合：本机无法运行 Tailscale 或策略限制；需要你保持 cloudflared 进程常驻。

1) 启动 cloudflared（会打印临时公网 URL）：

```bash
brew install cloudflared
cloudflared tunnel --url http://127.0.0.1:8788 --no-autoupdate
```

2) 用该 URL 作为 push endpoint 执行 setup：

```bash
PUSH_TOKEN="$(python3 - <<'PY'
import secrets
print(secrets.token_hex(24))
PY
)"

openclaw webhooks gmail setup \
  --account 你的Gmail@gmail.com \
  --tailscale off \
  --push-token "$PUSH_TOKEN" \
  --push-endpoint "https://<your-trycloudflare-host>/gmail-pubsub?token=$PUSH_TOKEN"

openclaw gateway restart
```

---

## 4. 配置“收到邮件就发飞书通知”

在 `~/.openclaw/openclaw.json` 的 `hooks.mappings` 里增加（或覆盖）`path: "gmail"` 的 mapping：

```json5
{
  hooks: {
    enabled: true,
    presets: ["gmail"],
    mappings: [
      {
        match: { path: "gmail" },
        action: "agent",
        wakeMode: "now",
        name: "Gmail",
        sessionKey: "hook:gmail:{{messages[0].id}}",
        messageTemplate:
          "【Gmail 新邮件】\n来自：{{messages[0].from}}\n主题：{{messages[0].subject}}\n摘要：{{messages[0].snippet}}\n\n请仅用一句话回复：已收到邮件并已通知到飞书。",
        deliver: true,
        channel: "feishu",
        to: "ou_xxx" // 你的飞书 open_id；群聊用 oc_xxx(chat_id)
      }
    ]
  }
}
```

### 4.1 获取飞书 open_id / chat_id

- 在飞书里先给机器人发一条消息，然后：

```bash
openclaw channels resolve
```

按提示选择飞书会话即可拿到 open_id/chat_id。

### 4.2 飞书 dmPolicy=open 的必要配置

若 `channels.feishu.dmPolicy="open"`，请确保：

```json5
channels: {
  feishu: {
    dmPolicy: "open",
    allowFrom: ["*"]
  }
}
```

---

## 5. 验证与成功判定

### 5.1 发测试邮件

```bash
gog gmail send --account 你的Gmail@gmail.com --to 你的Gmail@gmail.com --subject "test" --body "ping"
```

### 5.2 看日志（最可靠）

```bash
openclaw logs --max-bytes 200000 | grep -E "gmail-watcher|hook:gmail:|\\[feishu\\] sent text messageId="
```

看到：
- `gog gmail watch serve ... listening ...`
- `hook:gmail:<id>`（hook 被触发）
- `[feishu] sent text messageId=... to=ou_...`（飞书发送成功）

---

## 6. 想“改变这个 webhook”要怎么配置？

你可以改三类东西：

### 6.1 改 Hook 入口（Gateway Webhook）

| 配置 | 作用 |
|------|------|
| `hooks.path` | Webhook 基础路径，默认 `/hooks`（最终为 `/hooks/gmail`） |
| `hooks.token` | 保护 webhook 的 token（`Authorization: Bearer <token>` / `x-openclaw-token` / `?token=`） |

改完后需要 **重启 Gateway**（或至少触发 reload），并确保 `gog gmail watch serve` 的 `--hook-url` 指向新路径。

### 6.2 改 Gmail Push 接收路径（gog watch serve）

| 配置 | 作用 |
|------|------|
| `hooks.gmail.serve.bind/port/path` | 本机接收 Pub/Sub push 的监听地址与路径（默认 127.0.0.1:8788 + `/gmail-pubsub`） |
| `hooks.gmail.pushToken` | push endpoint 的共享 token（`x-gog-token` 或 `?token=`） |

> 重要：你把 `serve.path` 改了，就必须同步修改 **push endpoint URL**（Pub/Sub subscription 的 push-endpoint）。

### 6.3 改“发到哪里”（飞书/其它渠道）

改 `hooks.mappings` 里：
- `deliver: true`
- `channel`: `"feishu"`（或其它渠道）
- `to`: 目标 open_id/chat_id（或渠道目标）
- `messageTemplate`: 通知内容模板

---

## 7. 可选：飞书里让 Agent 发邮件到 Gmail（gmail_send）

这是“从对话发信到 Gmail”的能力，与“收信触发”是两条独立链路。

前置条件：
- 本机 `gog` 已授权（`gog auth list`）
- 配置 `hooks.gmail.account` 为发件账号（通常与收信 watch 使用同一账号）

验证方式：
- 在飞书里对机器人说：让它调用 `gmail_send` 发一封测试邮件到你的邮箱
- 或在本机用 `openclaw agent --local` 指令让 Agent 调用 `gmail_send`

---

## 8. 故障排查（最常见）

| 现象 | 结论 | 处理 |
|------|------|------|
| 收到邮件但飞书没通知 | 多数是 watcher 未启动 / push 没到本机 | `openclaw logs` 查 `gmail watcher not started: gmail topic required`；重新跑 `openclaw webhooks gmail setup` |
| `gmail watcher not started: gmail topic required` | 缺 `hooks.gmail.topic` | 说明 setup 未完成 |
| 需要公网 push 但 Tailscale 起不来 | 无公网入口 | 用 cloudflared 备选方案 |
| 端口 8788 占用 | serve 起不来 | 关闭重复的 `gog gmail watch serve`/`openclaw webhooks gmail run` |

---

## 9. 附：验证脚本（保留）

- `doc/sum/scripts/verify-gmail-webhook.sh`：发测试邮件 + 提示如何查日志
- `doc/sum/scripts/verify-gmail-webhook-feishu.sh`：端到端验证（发信 + 查 hook/飞书投递日志）

---

## 10. 其它邮箱自动收件方案（设计草案）

在实现 Gmail 官方 Webhook 方案之前，曾设计过一套通用「邮箱自动收件 + AI 总结 + 通知」架构（基于 IMAP 监听服务）。当前代码已经采用 **Gmail Webhook 官方链路**，以下内容仅作**未来扩展到其他邮箱（QQ 邮箱 / 企业邮箱等）时的设计参考**：

- 使用 Python/Node 监听 IMAP（IDLE）新邮件；
- 收到新邮件后解析发件人/主题/正文/附件；
- 调用 DashScope（如 `qwen-max`）生成结构化总结；
- 通过 OpenClaw Webhook 或飞书/Discord API 推送通知。

如果以后要支持「非 Gmail 的其它邮箱自动收件」，可以沿用这套架构，将 **IMAP 监听服务** 作为「外部 watcher」，通过当前文档中的 `/hooks/...` 和 `hooks.mappings` 把摘要交给 OpenClaw 处理并转发到飞书。

