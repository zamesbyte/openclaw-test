# Feishu Bot Setup Guide for OpenClaw

## 飞书机器人创建指南

本指南记录了在飞书开放平台创建 OpenClaw AI 助手机器人应用的完整步骤。

> **应用管理页面**: https://open.feishu.cn/app/cli_a91a26d46278dcbd

---

## 步骤 1: 访问飞书开放平台 ✅ 已完成

1. 打开浏览器访问: https://open.feishu.cn/app
2. 使用飞书账号登录

---

## 步骤 2: 创建企业自建应用 ✅ 已完成

- **应用名称**: `openclaw-feishu`
- **App ID**: `cli_a91a26d46278dcbd`

---

## 步骤 3: 获取应用凭证 ✅ 已完成

- **App ID**: `cli_a91a26d46278dcbd`
- **App Secret**: 已配置到 OpenClaw (值: `psPh...FYlH`)

OpenClaw 配置命令:
```bash
openclaw config set channels.feishu.appId "cli_a91a26d46278dcbd"
openclaw config set channels.feishu.appSecret "你的App Secret"
```

---

## 步骤 4: 启用机器人能力 ⬅️ 待完成

> 打开: https://open.feishu.cn/app/cli_a91a26d46278dcbd

1. 在左侧菜单中点击 **"添加应用能力"** 或 **"应用能力"** > **"机器人"**
2. 点击 **"启用机器人"** 按钮
3. 设置机器人名称: `openclaw-feishu`
4. 点击 **"保存"**

---

## 步骤 5: 配置应用权限 ⬅️ 待完成

1. 在左侧菜单中点击 **"权限管理"**
2. 点击 **"批量导入"** 按钮
3. 粘贴以下 JSON 配置:

```json
{
  "scopes": {
    "tenant": [
      "aily:file:read",
      "aily:file:write",
      "application:application.app_message_stats.overview:readonly",
      "application:application:self_manage",
      "application:bot.menu:write",
      "contact:user.employee_id:readonly",
      "corehr:file:download",
      "event:ip_list",
      "im:chat.access_event.bot_p2p_chat:read",
      "im:chat.members:bot_access",
      "im:message",
      "im:message.group_at_msg:readonly",
      "im:message.p2p_msg:readonly",
      "im:message:readonly",
      "im:message:send_as_bot",
      "im:resource"
    ],
    "user": [
      "aily:file:read",
      "aily:file:write",
      "im:chat.access_event.bot_p2p_chat:read"
    ]
  }
}
```

4. 点击 **"确定"** 完成权限导入

### 权限说明

核心权限包括:
- `im:message` - 发送消息
- `im:message:send_as_bot` - 以机器人身份发送消息
- `im:message.p2p_msg:readonly` - 读取单聊消息
- `im:message.group_at_msg:readonly` - 读取群聊 @ 消息
- `im:message:readonly` - 读取消息
- `im:resource` - 访问资源文件
- `im:chat.members:bot_access` - 访问群成员信息
- `im:chat.access_event.bot_p2p_chat:read` - 读取单聊事件

---

## 步骤 6: 配置事件订阅 ⬅️ 关键步骤

> 前置条件已满足: OpenClaw 已配置飞书凭证, Gateway 正在运行

配置步骤:

1. 在左侧菜单中点击 **"事件订阅"**
2. 选择 **"使用长连接接收事件"** (WebSocket 方式)
3. 点击 **"添加事件"** 按钮
4. 搜索并添加事件: `im.message.receive_v1`
5. 点击 **"保存"**

### 为什么使用长连接?

- ✅ 无需公网 IP 或域名
- ✅ 无需配置 webhook URL
- ✅ 更安全,不暴露服务端点
- ✅ 实时接收消息,延迟更低

---

## 步骤 7: 创建版本并发布 ⬅️ 待完成

1. 在左侧菜单中点击 **"版本管理与发布"**
2. 点击 **"创建版本"** 按钮
3. 填写版本信息:
   - **版本号**: `1.0.0`
   - **更新说明**: `初始版本 - OpenClaw AI 助手`
4. 点击 **"保存"**
5. 点击 **"申请发布"** 按钮
6. 等待管理员审批(企业自建应用通常会自动通过)

---

## 步骤 8: 配置 OpenClaw ✅ 已完成

已通过命令行完成配置:

```bash
openclaw config set channels.feishu.appId "cli_a91a26d46278dcbd"
openclaw config set channels.feishu.appSecret "psPhaPEDZvOJ9aU6wSLzxcNVavd8FYlH"
openclaw gateway restart
```

验证结果: `openclaw status --deep` 显示 Feishu: OK

---

## 步骤 9: 启动并测试

### 1. 启动 OpenClaw Gateway

```bash
cd openclaw-src
openclaw gateway
```

或者在后台运行:

```bash
openclaw gateway install
openclaw gateway start
```

### 2. 检查 Gateway 状态

```bash
openclaw gateway status
```

### 3. 查看日志

```bash
openclaw logs --follow
```

### 4. 在飞书中测试

1. 在飞书中搜索并找到你的机器人 "OpenClaw AI助手"
2. 发送一条测试消息,例如: `你好`
3. 机器人会回复一个配对码(pairing code)

### 5. 批准配对

```bash
# 查看待配对请求
openclaw pairing list feishu

# 批准配对(将 <CODE> 替换为实际的配对码)
openclaw pairing approve feishu <CODE>
```

批准后,就可以正常与机器人对话了!

---

## 配置说明

### 访问控制策略

#### 私聊策略 (dmPolicy)

- `"pairing"` (默认): 新用户需要配对码,管理员批准后才能使用
- `"allowlist"`: 只允许白名单中的用户
- `"open"`: 允许所有用户(需要在 allowFrom 中添加 "*")
- `"disabled"`: 禁用私聊

#### 群聊策略 (groupPolicy)

- `"open"` (默认): 允许所有群聊
- `"allowlist"`: 只允许白名单中的群聊
- `"disabled"`: 禁用群聊

#### 是否需要 @ 提及 (requireMention)

- `true` (默认): 在群聊中需要 @ 机器人才会响应
- `false`: 群聊中所有消息都会响应

### 获取用户和群组 ID

#### 获取用户 Open ID (ou_xxx)

1. 启动 Gateway 并让用户私聊机器人
2. 运行 `openclaw logs --follow` 查看日志中的 `open_id`

或者:

```bash
openclaw pairing list feishu
```

#### 获取群组 Chat ID (oc_xxx)

1. 启动 Gateway 并在群聊中 @ 机器人
2. 运行 `openclaw logs --follow` 查看日志中的 `chat_id`

---

## 常见问题

### 1. 机器人在群聊中不响应

- ✅ 确保机器人已被添加到群聊
- ✅ 确保在消息中 @ 了机器人(默认行为)
- ✅ 检查 `groupPolicy` 是否为 `"disabled"`
- ✅ 查看日志: `openclaw logs --follow`

### 2. 机器人收不到消息

- ✅ 确保应用已发布并通过审批
- ✅ 确保事件订阅中包含 `im.message.receive_v1`
- ✅ 确保选择了 **"使用长连接接收事件"**
- ✅ 确保应用权限配置完整
- ✅ 确保 Gateway 正在运行: `openclaw gateway status`
- ✅ 查看日志: `openclaw logs --follow`

### 3. App Secret 泄露

1. 在飞书开放平台重置 App Secret
2. 更新 OpenClaw 配置中的 App Secret
3. 重启 Gateway

### 4. 消息发送失败

- ✅ 确保应用有 `im:message:send_as_bot` 权限
- ✅ 确保应用已发布
- ✅ 查看日志获取详细错误信息

---

## 配置完成后的检查清单

- [ ] App ID 和 App Secret 已复制
- [ ] 机器人能力已启用
- [ ] 应用权限已配置(批量导入 JSON)
- [ ] 事件订阅已配置(长连接 + im.message.receive_v1)
- [ ] 应用版本已创建并发布
- [ ] OpenClaw 配置已更新
- [ ] Gateway 已启动并运行正常
- [ ] 已在飞书中测试并成功配对

---

## 下一步

配置完成后,你可以:

1. **添加更多功能**: 查看 OpenClaw 文档了解更多功能
2. **配置多个机器人**: 在 `accounts` 中添加多个账号
3. **自定义系统提示词**: 在配置中添加 `systemPrompt`
4. **配置群聊白名单**: 使用 `groupAllowFrom` 限制可用群聊
5. **启用 Feishu 工具**: 配置 `tools` 启用文档、云盘等功能

参考文档:
- OpenClaw Feishu 频道文档: `openclaw-src/docs/channels/feishu.md`
- 配置参考: `openclaw-src/src/config/zod-schema.ts`

---

## 附录: 完整配置示例

```json
{
  "channels": {
    "feishu": {
      "enabled": true,
      "domain": "feishu",
      "connectionMode": "websocket",
      "dmPolicy": "pairing",
      "groupPolicy": "allowlist",
      "requireMention": true,
      "textChunkLimit": 2000,
      "mediaMaxMb": 30,
      "historyLimit": 20,
      "dmHistoryLimit": 50,
      "markdown": {
        "mode": "native",
        "tableMode": "native"
      },
      "renderMode": "auto",
      "blockStreamingCoalesce": {
        "enabled": true,
        "minDelayMs": 100,
        "maxDelayMs": 1000
      },
      "tools": {
        "doc": true,
        "wiki": true,
        "drive": true,
        "perm": false,
        "scopes": true
      },
      "accounts": {
        "main": {
          "name": "OpenClaw AI助手",
          "appId": "cli_xxxxxxxxxx",
          "appSecret": "你的 App Secret",
          "enabled": true
        }
      },
      "allowFrom": [],
      "groupAllowFrom": [],
      "groups": {}
    }
  }
}
```

---

---

> 最后更新: 2026-02-14
