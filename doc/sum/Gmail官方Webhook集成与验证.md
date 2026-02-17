# Gmail 官方 Webhook 集成与验证

> 采用 OpenClaw 官方方式：Gmail Watch → Pub/Sub → `gog gmail watch serve` → OpenClaw `/hooks/gmail`。  
> 官方文档：[Gmail PubSub](https://docs.openclaw.ai/automation/gmail-pubsub)  
> 更新日期：2026-02-17

---

## 一、前置条件（必须全部满足）

| 依赖 | 说明 | 检查方式 |
|------|------|----------|
| **gcloud** | 已安装并登录，项目与 gog OAuth 同项目 | `gcloud auth list`、`gcloud config get project` |
| **gog (gogcli)** | 已安装并完成 Gmail 授权 | `gog auth list` |
| **Tailscale** | 已安装且**当前处于运行状态** | `tailscale status` 无报错 |
| **OpenClaw** | Gateway 可访问 | `openclaw gateway status` 或 `openclaw config get hooks` |

**重要**：执行 `openclaw webhooks gmail setup` 前，必须先启动 Tailscale（否则会报 `failed to connect to local Tailscale service`）。  
- macOS：打开 Tailscale 应用，或终端执行 `tailscale up`  
- 确认：`tailscale status --json` 能正常返回

---

## 二、一键配置（推荐）

```bash
# 1. 确认 Tailscale 已运行
tailscale status

# 2. 执行官方向导（会写 hooks 配置、创建 Topic/Subscription、设置 Gmail Watch、Tailscale Funnel）
openclaw webhooks gmail setup --account 你的Gmail@gmail.com

# 3. 重启 Gateway，使 Gateway 自动启动 gog gmail watch serve
openclaw gateway restart
```

完成后，新邮件进入该 Gmail 收件箱时会触发 Pub/Sub 推送 → 本地 serve → OpenClaw `/hooks/gmail` → Agent 处理（可配置回复邮件）。

### 2.1 无法使用 Tailscale 时（备选：cloudflared 临时公网 URL）

> 说明：这是官方文档中提到的「高级/DIY」方式（不走 Tailscale Funnel）。适合本机无法运行 Tailscale 或企业策略限制时，用于快速打通验证。

1. 安装并启动 cloudflared：

```bash
brew install cloudflared
cloudflared tunnel --url http://127.0.0.1:8788 --no-autoupdate
```

记下输出的临时 URL（形如 `https://xxxx.trycloudflare.com`），并**保持该进程运行**。

2. 用该 URL 作为 Pub/Sub push endpoint 执行 setup（示例）：

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
```

3. 重启 Gateway：

```bash
openclaw gateway restart
```

---

## 三、验证步骤

### 3.1 发送测试邮件

向 `hooks.gmail.account` 对应的邮箱发一封邮件，例如：

- **主题**：`OpenClaw Webhook 验证`
- **正文**：`请用一句话回复当前时间。`

也可用脚本发送（见下方「验证脚本」）。

### 3.2 如何确认 Webhook 已触发

1. **Gateway 日志**（含 gmail-watcher、hook 请求）  
   ```bash
   openclaw logs --max-bytes 50000 | grep -iE 'gmail|hook|8788'
   ```
2. **Gmail Watch 状态**  
   ```bash
   gog gmail watch status --account 你的Gmail@gmail.com
   ```
3. **收件箱**：若配置了 Agent 回复（`deliver` + 回信），发件人应收到 AI 回复邮件。

### 3.3 成功判定

- 发信后数秒到一分钟内，日志中出现与 `gmail`/`hook`/`8788` 相关的请求或 watcher 活动；
- 且/或 发件人收到 OpenClaw Agent 的回复邮件。

若长时间无任何日志或回复，请按下方「故障排查」检查。

---

## 四、验证脚本（可选）

项目内提供脚本，向当前配置的 Gmail 账号发一封测试邮件，便于触发 Webhook 并对照日志检查：

```bash
# 从项目 doc/sum 目录执行
cd /path/to/openclaw/doc/sum
./scripts/verify-gmail-webhook.sh
```

脚本会：  
- 读取 `openclaw config get hooks.gmail.account` 得到邮箱；  
- 使用 `gog gmail send` 向该邮箱发一封测试邮件；  
- 输出「如何检查验证结果」的提示（日志命令、成功判定）。

---

## 五、日常使用

- **收邮件即触发**：发到 `hooks.gmail.account` 的邮件会进入 OpenClaw Hook，由 Agent 处理。  
- **回复行为**：在 `~/.openclaw/openclaw.json` 的 `hooks.mappings` 中为 `path: "gmail"` 配置 `deliver: true` 及可选 `channel`/`to`，即可让 AI 通过 `gog gmail send` 回信。详见 [Gmail PubSub](https://docs.openclaw.ai/automation/gmail-pubsub) 中的 `messageTemplate`、`deliver`、`channel` 配置。  
- **收信时通知到飞书**：在 mapping 中设置 `deliver: true`、`channel: "feishu"`、`to: "你的飞书 open_id 或 chat_id"`，即可在收到 Gmail 时在飞书收到一条通知。若使用 `channel: "last"`（不设 `to`），则发到最近一次对话（需先在飞书里给机器人发过消息）。详见 [Gmail 收信通知到飞书](./scripts/gmail-webhook-deliver-to-feishu.md)。

---

## 六、故障排查

| 现象 | 可能原因 | 处理 |
|------|----------|------|
| `tailscale status --json failed` | Tailscale 未运行 | 启动 Tailscale 后重新执行 `openclaw webhooks gmail setup` |
| `Invalid topicName` | Pub/Sub Topic 与 OAuth 项目不一致 | 使用与 gog 相同的 GCP 项目：`gcloud config set project <id>` |
| `User not authorized` | Topic 未授权 Gmail 推送 | 向导会执行 `add-iam-policy-binding`；若手动建 Topic，需添加 `gmail-api-push@system.gserviceaccount.com` 的 `roles/pubsub.publisher` |
| 收邮件后无日志、无回复 | Push 未到达本机 / serve 未启动 / Hook 未启用 | 检查 Tailscale Funnel、Gateway 是否已重启、`hooks.enabled` 与 `hooks.gmail.account` 是否已配置；确认未同时运行 `openclaw webhooks gmail run`（避免 8788 冲突） |
| `listen tcp 127.0.0.1:8788: bind: address already in use` | 端口被占用 | 关闭重复的 `gog gmail watch serve` 或 `openclaw webhooks gmail run`，仅保留 Gateway 自动启动的 watcher |

更多见官方文档 [Troubleshooting](https://docs.openclaw.ai/automation/gmail-pubsub#troubleshooting)。

---

## 七、参考

- 官方 Gmail Webhook：<https://docs.openclaw.ai/automation/gmail-pubsub>  
- 本地详细安装与架构：`doc/sum/Gmail配置为OpenClaw专属Channel.md`
