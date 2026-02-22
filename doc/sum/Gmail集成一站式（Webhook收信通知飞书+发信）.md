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

> **注意**：`trycloudflare.com` 为临时隧道，**重启或退出 cloudflared 后 URL 会变**，需用新 URL 再执行一次 setup。长期使用建议 Tailscale 或自建命名隧道。

### 3.3 本地服务内网穿透一键脚本（推荐）

可直接执行脚本完成「公网可达 + Gmail setup」：

```bash
# 优先 Tailscale，若未运行则自动用 cloudflared
bash doc/sum/scripts/gmail-push-expose.sh

# 仅用 Tailscale（需已 tailscale up）
bash doc/sum/scripts/gmail-push-expose.sh tailscale

# 仅用 cloudflared（会后台启动隧道并执行 setup）
bash doc/sum/scripts/gmail-push-expose.sh cloudflared
```

脚本会：读取 `hooks.gmail.account`；若选 Tailscale 则执行 `openclaw webhooks gmail setup --account <Gmail>`；若选 cloudflared 则启动隧道、解析 trycloudflare URL、执行 setup 并写入当前 pushToken。执行完成后按提示执行 `openclaw gateway restart`。

飞书/Discord 消息失败、发信与 Gmail→飞书 的更多根因与验证见：`doc/sum/通道故障诊断与修复.md`（第八、九节）。

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
- 使用的 Agent 的 **tools.profile** 需包含 `gmail_send` 或 `group:messaging`（否则 Agent 不会调用发信工具）

验证方式：
- **飞书**：对机器人说「给我邮箱发个测试邮件，地址：xxx@gmail.com」，若该 Agent 的 **tools.allow** 含 `gmail_send`（或 `group:messaging`）会直接发信。
- **本机 CLI**：`openclaw agent --agent main --message "给我邮箱发个测试邮件，地址：lifeng.zhan90@gmail.com"`（或 `--agent shop-hunter`，需该 agent 已配置 `tools.allow` 含 `gmail_send`）。
- **未开放 gmail_send 时**：在 `~/.openclaw/openclaw.json` 的对应 agent（如 `agents.list` 中 id 为 `shop-hunter` 或 `main` 的项）的 `tools.allow` 数组中增加 `"gmail_send"`，保存后执行 `openclaw gateway restart`，新会话会带上该工具。也可用 gog 直接验证：`gog gmail send --to <收件人> --subject "测试" --body "正文"`。

### 7.1 Dashboard Chat（agent:main:main）与 main agent

Control UI 的默认会话是 **`agent:main:main`**，若配置里没有 id 为 **main** 的 agent，则不会解析到任何 agent 的 tools，发信能力可能不可用。

**根因与正确配置：**

- Dashboard Chat 使用会话 `agent:main:main`。工具列表先按 **profile**（如 `coding`）过滤，再按 agent 的 allow/deny 过滤。**profile "coding" 的 allow 里没有 `gmail_send`（属于 group:messaging）**，因此仅写 `tools.allow: ["gmail_send"]` 时，`gmail_send` 会在 profile 阶段就被滤掉，模型拿不到该工具。
- 正确做法：在对应 agent 的 `tools` 里使用 **`tools.alsoAllow`**，在 profile 阶段把 `gmail_send` 加进允许列表。配置不允许同一层同时写 `allow` 和 `alsoAllow`，因此用 **`profile: "coding"` + `alsoAllow: ["browser", "gmail_send"]`**（不再单独写 `allow`），例如：
  ```json
  "tools": {
    "profile": "coding",
    "alsoAllow": ["browser", "gmail_send"],
    "deny": ["group:runtime", "nodes", "cron", "gateway"]
  }
  ```
- 在 `agents.list` 中需有 id 为 `main` 的 agent（供 `agent:main:main` 解析），且其 `tools` 按上方式包含 `gmail_send`。

**验证**：在 Dashboard Chat（会话 `agent:main:main`）或 CLI（`openclaw agent --agent main -m "请给我的邮箱发一封测试邮件, 主题和内容自拟, 收件人: xxx@gmail.com"`）中发起发信请求，Agent 应调用 `gmail_send` 并实际发信。

---

## 8. 故障排查（最常见）

### 8.1 收到邮件后仍然没有飞书推送（按顺序做）

**① 先确认「OpenClaw 侧」是否正常**

不依赖真实 Gmail 收信，直接模拟 Hook，看飞书能否收到：

```bash
bash doc/sum/scripts/verify-gmail-hook-to-feishu.sh
```

- 若脚本报 [OK]、且飞书里能看到「Gmail→飞书 链路测试」消息 → OpenClaw 配置与投递正常，问题在 **②**。
- 若飞书收不到 → 检查 `hooks.mappings` 里 Gmail 的 `channel: "feishu"`、`to: "ou_xxx"`（你的 open_id）、`deliver: true`，以及 `openclaw channels resolve` 拿到的 open_id 是否一致。

**② 再确认「Google Push 能到本机」（根因多在此处）**

Gmail 新邮件是靠 **Google Cloud Pub/Sub 往你本机推** 才会触发 Hook；推不到就永远不会触发。若配置里 **`hooks.gmail.tailscale.mode` 为 `off`** 且未配置 `--push-endpoint`，则当前注册的 push 地址很可能是不可达的，真实收信不会触发。

- **Tailscale（推荐）**：  
  ```bash
  tailscale status   # 确认已登录（若未登录则 tailscale up）
  openclaw webhooks gmail setup --account 你的Gmail@gmail.com
  openclaw gateway restart
  ```  
  会注册/续期 Gmail Watch，并**把 Pub/Sub 的 push endpoint 设为你的 Tailscale Funnel 公网 URL**，Google 才能推到你本机。若此前用 `--tailscale off` 跑过 setup，需要**重新跑一次**（不传 `--tailscale off`）以更新 endpoint。
- **不用 Tailscale**：必须用 **cloudflared** 等隧道，把公网 URL 暴露到本机 `gog gmail watch serve` 监听的端口（默认 8788），并用 `--push-endpoint` 执行 setup（见 3.2 方案 B）。

**③ 看日志确认 Push 是否到达**

```bash
openclaw logs --max-bytes 200000 | grep -E "gmail-watcher|gog.*gmail|hooks/gmail|hook:gmail|feishu.*sent"
```

- 有 `gmail watcher started`、`[gog]` 收到请求、`hooks/gmail` 或 `hook:gmail:` → Push 已到，再查 mapping/飞书 to。
- 完全没有 gmail/hook 相关 → Push 没到本机，回到 ② 检查 Tailscale/隧道和 `openclaw webhooks gmail setup`。

### 8.2 深度诊断（逐环检查）

不只看状态，从**根本**上逐环验证整条链路，可运行：

```bash
bash doc/sum/scripts/diagnose-gmail-to-feishu.sh
```

脚本会依次检查：① `hooks.gmail` 配置（account、topic、pushToken、tailscale）；② 公网 Push 是否可达（Tailscale/cloudflared）；③ Gateway 与 8788 端口（gog serve 是否在监听）；④ 模拟 Hook→飞书 是否成功；⑤ 近期日志中是否有 watcher/Hook/飞书发送。根据输出定位断点并按 8.1 修复。

### 8.3 其它常见问题

| 现象 | 结论 | 处理 |
|------|------|------|
| 收到邮件但飞书没通知 | 多数是 push 没到本机 | 先跑 8.1 ① 再跑 8.2 诊断脚本，按 8.1 ②③ 修复 |
| `gmail watcher not started: gmail topic required` | 缺 `hooks.gmail.topic` | 执行 `openclaw webhooks gmail setup --account <Gmail>` |
| 需要公网 push 但 Tailscale 起不来 | 无公网入口 | 用 cloudflared（3.2 方案 B） |
| 端口 8788 占用 | serve 起不来 | 关闭重复的 `gog gmail watch serve` 或设 `OPENCLAW_SKIP_GMAIL_WATCHER=1` |

---

## 9. 附：验证与诊断脚本

- `doc/sum/scripts/gmail-push-expose.sh`：**本地内网穿透 + Gmail setup 一键脚本**（Tailscale 或 cloudflared）
- `doc/sum/scripts/verify-gmail-hook-to-feishu.sh`：模拟 POST /hooks/gmail，验证 OpenClaw→飞书 是否正常
- `doc/sum/scripts/diagnose-gmail-to-feishu.sh`：**深度诊断** Gmail→飞书 全链路（配置、Push 可达性、进程、日志）
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

