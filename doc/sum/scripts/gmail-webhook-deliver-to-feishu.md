# Gmail 收信时通知到飞书

收到 Gmail 邮件后，由 OpenClaw 将一条通知发到你的飞书（私聊或群）。

## 1. 配置方式

在 `~/.openclaw/openclaw.json` 的 `hooks` 中确保：

- `hooks.enabled` 为 `true`
- `hooks.token` 已设置（若未设置，运行 `openclaw webhooks gmail setup` 会自动写入）
- `hooks.presets` 包含 `"gmail"`
- 通过 `hooks.mappings` 覆盖 Gmail 的投递目标为飞书

**示例（发到飞书指定用户/群）**：

```json
{
  "hooks": {
    "enabled": true,
    "token": "你的 hook token",
    "path": "/hooks",
    "presets": ["gmail"],
    "mappings": [
      {
        "match": { "path": "gmail" },
        "action": "agent",
        "wakeMode": "now",
        "name": "Gmail",
        "sessionKey": "hook:gmail:{{messages[0].id}}",
        "messageTemplate": "【Gmail 新邮件】\n来自：{{messages[0].from}}\n主题：{{messages[0].subject}}\n摘要：{{messages[0].snippet}}\n\n请仅用一句话回复：已收到邮件并已通知到飞书。",
        "deliver": true,
        "channel": "feishu",
        "to": "你的飞书 open_id 或 chat_id"
      }
    ],
    "gmail": { "account": "你的Gmail@gmail.com" }
  }
}
```

- **channel**：固定为 `"feishu"` 表示发到飞书。
- **to**：飞书接收人：
  - **私聊**：填你的 **open_id**（形如 `ou_xxxx`），或 `open_id:ou_xxxx`。
  - **群聊**：填该群的 **chat_id**（形如 `oc_xxxx`），或 `chat_id:oc_xxxx`。

**注意**：Gmail 由 **Webhook 触发**，每次是**新会话**（sessionKey 为 `hook:gmail:<消息id>`），没有“最近会话”可沿用，因此 **`channel: "last"` 不会发到飞书**（会落空或落到默认渠道）。要稳定收到通知，请务必使用 **`channel: "feishu"` + `to: "你的 open_id"`**。

若仍想用「最近会话」（仅适合非 Webhook 场景），可设 `"deliver": true`、`"channel": "last"` 并去掉 `"to"`。

## 2. 如何获取飞书 open_id / chat_id

- **open_id（推荐）**：在飞书里先给机器人发一条消息，然后执行：
  ```bash
  openclaw channels resolve
  ```
  按提示选择飞书会话，会解析出 open_id 或 chat_id。
- 或参考 [飞书渠道文档](https://docs.openclaw.ai/channels/feishu) 中的「Allowlist Feishu DMs by open_id」等说明，从管理后台/API 获取。

## 3. 验证

**自动验证（推荐）**：在项目根目录执行（会检查配置、重启 Gateway、发测试邮件、查日志）：

```bash
OPENCLAW_CLI="node openclaw-src/dist/index.js" doc/sum/scripts/verify-gmail-webhook-feishu.sh
```

需先在工作区执行过 `npm run build`（以便 `channel: "feishu"` 通过配置校验）。验证通过后请到飞书确认是否收到通知。

**手动验证**：保存配置后重启 Gateway，向 `hooks.gmail.account` 发一封测试邮件，在飞书中查看是否收到「已收到邮件并已通知到飞书」类通知。若未收到，请检查 Gateway 日志（`openclaw logs --max-bytes 50000 | grep -iE 'gmail|hook|feishu'`）、Gmail Webhook 是否已按 [Gmail官方Webhook集成与验证](../Gmail官方Webhook集成与验证.md) 完成（Tailscale、setup、watch serve）。
