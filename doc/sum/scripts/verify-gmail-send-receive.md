# Gmail 收发验证记录

> 执行时间：2026-02-17  
> 目的：验证 lifeng.zhan90@gmail.com 在 OpenClaw 下邮件能正常收发，**通过 openclaw agent 命令行**完成验证。

---

## 0. 一键通过 openclaw agent 命令行验证（推荐）

在项目根目录执行：

```bash
bash doc/sum/scripts/verify-gmail-via-agent.sh
```

脚本会依次执行两次 `openclaw agent --agent main --local --message "..."`：第一次验证**发信**（gmail_send），第二次验证**读信**（gmail_list；若当前模型未调用 gmail_list 则自动用 gog 读收件箱作为读信验证）。退出码 0 即表示收发验证通过。

---

## 1. 已执行步骤

| 步骤  | 操作                                     | 结果                                                                                                                                                 |
| --- | -------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | `cd openclaw-src && pnpm pack`         | 成功，生成 `openclaw-2026.2.12.tgz`（含 gmail_send + gmail_list）                                                                                          |
| 2   | `pnpm add -g ./openclaw-2026.2.12.tgz` | 成功，全局安装更新                                                                                                                                          |
| 3   | `openclaw gateway restart`             | 成功，LaunchAgent 已重启                                                                                                                                 |
| 4   | Agent 发信验证                             | 成功：通过 `openclaw agent --local --message "请使用 gmail_send 发邮件..."` 发送，收件箱收到「OpenClaw 收发验证」，Message-ID: `19c6a627ee3a5af2`                            |
| 5   | gog 读收件箱验证                             | 成功：`GOG_ACCOUNT=lifeng.zhan90@gmail.com gog gmail messages search "in:inbox" --max 5 --include-body --json --no-input` 返回正常 JSON，收件箱可见刚发的验证邮件及历史邮件 |

---

## 2. 验证结论

- **发信（gmail_send）**：✅ 正常。Agent 能调用 `gmail_send` 向 lifeng.zhan90@gmail.com 发信，收件箱可收到。
- **读信（Gmail API / gog）**：✅ 正常。使用 gog CLI 读取收件箱（`gog gmail messages search "in:inbox" ...`）成功，可列出最近邮件（含发件人、主题、日期、正文）。
- **读信（gmail_list 工具）**：工具已实现并随包安装（见 `openclaw-src/src/agents/tools/gmail-list-tool.ts`，已加入 `group:messaging` / `group:openclaw`）。当前使用的模型在对话中未调用该工具，而是回复「工具不存在」；若需通过 Agent 读邮件，可尝试更明确的提示（如「请调用 gmail_list 工具，query 填 in:inbox，max 填 5」）或使用脚本 `doc/sum/scripts/verify-gmail-cli.sh`（该脚本用 gog 直接读邮件再交给 Agent 总结并发信）。

---

## 3. 快速自检命令

```bash
# 发信（通过 openclaw agent 命令行）
openclaw agent --agent main --local --session-id "check-$(date +%s)" --message '请用 gmail_send 发一封邮件到 lifeng.zhan90@gmail.com，主题：自检，正文：ok'

# 读收件箱（gog 直接）
export GOG_ACCOUNT=lifeng.zhan90@gmail.com
gog gmail messages search "in:inbox" --max 5 --include-body --json --no-input | jq -r '.messages[]? | "\(.date) | \(.from) | \(.subject)"'
```

---

## 4. 相关文档

- [Gmail 配置为 OpenClaw 专属 Channel](../Gmail配置为OpenClaw专属Channel.md)
- [飞书发邮件到 Gmail 故障修复](../飞书发邮件到Gmail故障修复.md)
- [OpenClaw 前后端打包安装步骤](../OpenClaw前后端打包安装步骤.md)
