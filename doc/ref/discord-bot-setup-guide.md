# Discord 机器人创建指南

> 目标: 创建名为 "openclaw-discord" 的 Discord 机器人

---

## 步骤 1: 创建应用

1. 打开 https://discord.com/developers/applications
2. 登录 Discord 账号 (如未登录)
3. 点击右上角 **"New Application"**
4. 输入名称: `openclaw-discord`
5. 勾选同意条款，点击 **"Create"**

---

## 步骤 2: 配置 Bot

1. 在左侧菜单点击 **"Bot"**
2. 在 **Privileged Gateway Intents** 部分，开启以下三个开关:
   - **Presence Intent** ✅
   - **Server Members Intent** ✅
   - **Message Content Intent** ✅ (关键! 否则无法读取消息内容)
3. 点击 **"Save Changes"**

---

## 步骤 3: 获取 Bot Token

1. 在 Bot 页面，点击 **"Reset Token"** 按钮
2. 可能需要输入密码或 2FA 验证码
3. **立即复制生成的 Token** (只显示一次!)
4. Token 格式类似: `MTIzNDU2Nzg5MDEyMzQ1Njc4OQ.AbCdEf.XXXXX...`

---

## 步骤 4: 生成邀请链接

1. 在左侧菜单点击 **"OAuth2"** > **"URL Generator"**
2. 在 SCOPES 中勾选: `bot`
3. 在 BOT PERMISSIONS 中勾选:
   - Send Messages
   - Read Message History
   - Add Reactions
   - Attach Files
   - Embed Links
   - Read Messages/View Channels
   - Use Slash Commands
4. 复制底部生成的 **URL**
5. 在浏览器中打开该 URL，选择你的服务器，点击 **"Authorize"**

---

## 步骤 5: 记录信息

完成后需要提供以下信息:

- **Application ID**: (在 General Information 页面)
- **Bot Token**: (步骤 3 中复制的)

将这两个值告诉我，我会自动完成 OpenClaw 配置。

---

## 常见问题

### Token 忘记复制了?
点击 "Reset Token" 重新生成即可。

### Bot 无法读取消息?
确保 Message Content Intent 已开启 (步骤 2)。

### Bot 无法加入服务器?
确保邀请链接包含了正确的权限 (步骤 4)。

---

> 最后更新: 2026-02-14
