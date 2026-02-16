## OpenClaw CLI 命令与用法总结

> 说明：梳理常用 `openclaw` 命令，重点标出与 Memory / QMD 切换和验证相关的 CLI。  
> 适用前提：全局配置 `~/.openclaw/openclaw.json` 已通过 `openclaw doctor --fix` 清理，未再包含旧版本 CLI 不认识的字段。

---

## 一、总览与注意事项

- **唯一全局配置**：所有 `openclaw` 命令默认读取 `~/.openclaw/openclaw.json`。
- **配置校验**：CLI 启动时会按内置 schema 校验配置；若有未知字段，会提示 `Config invalid`。  
  - 如遇到 `Unrecognized key: "xxx"`，优先执行一次：`openclaw doctor --fix`。
- **Memory 后端切换**：底层依据 `memory.backend`（`builtin` / `qmd`），并在网关启动时生效。
- **不与 dev 版 schema 冲突的原则**：全局配置中仅使用稳定字段；实验性字段推荐通过环境变量或本仓库 dev CLI 使用。

---

## 二、配置相关命令

### 2.1 查看与编辑配置

- **查看整个配置（原始 JSON）**

```bash
openclaw config print
```

- **按路径获取字段值**

```bash
openclaw config get memory.backend
openclaw config get agents.defaults.memorySearch.provider
```

- **设置字段值**

> 仅在配置已通过 `doctor --fix` 清理、无未知字段时报错时使用。

```bash
openclaw config set memory.backend builtin
openclaw config set memory.backend qmd
```

执行成功时，会提示：

> `Updated memory.backend. Restart the gateway to apply.`

- **在编辑器中打开配置文件**

```bash
openclaw config edit
```

等价于打开 `~/.openclaw/openclaw.json`。

### 2.2 配置诊断与修复

- **检查并修复配置（推荐先执行一次）**

```bash
openclaw doctor --fix
```

行为：

- 删除 CLI schema 不认识的字段（例如先前的 `agents.defaults.memorySearch.query.rerank`）；
- 更新 `~/.openclaw/openclaw.json` 并生成 `.bak` 备份；
- 输出诊断信息（Gateway、Node 版本、Plugins、Security 等）。

若仅想检查、不自动修复，可以执行：

```bash
openclaw doctor
```

### 2.3 安全与插件

- **安全检查**

```bash
openclaw security audit --deep
```

- **查看插件状态**（随 doctor 输出一起展示，通常无需单独命令）。

---

## 三、Gateway（网关）相关命令

Gateway 是 OpenClaw 的长驻服务，负责接受 UI/前端请求、调用模型与 Agent。

### 3.0 Gateway 地址到底是什么？

- **Web 控制台 / Dashboard 地址（HTTP）**  
  - 默认：`http://127.0.0.1:18789/`（或 `http://localhost:18789/`）  
  - 用途：在浏览器里打开「Gateway Dashboard / Control UI」。
- **Gateway WebSocket 地址（WS）**  
  - 默认：`ws://127.0.0.1:18789`  
  - 用途：Control UI、Nodes、工具客户端等通过这个地址与 Gateway 通信。

你截图里访问的是类似 `http://localhost:18789/overview`，页面右上角提示：

- `unauthorized (1008): unauthorized: gateway token mismatch (open the dashboard URL and paste the token in Control UI settings)`

这不是“地址错了”，而是**认证 token 不匹配**：

- Gateway 端要求一个 token（`gateway.auth.token` 或 `OPENCLAW_GATEWAY_TOKEN`）；  
- 控制台 UI 里保存的是另一个 token，于是握手失败就报 1008。

**修复方式：**

1. 推荐执行一次：

   ```bash
   openclaw dashboard
   ```

   这个命令会自动打开带 `?token=...` 的正确 URL，例如：  
   `http://127.0.0.1:18789/?token=<gateway-token>`，并把 token 写入浏览器的本地存储。

2. 或者手动：

   - 在终端查出当前 Gateway 的 token：

     ```bash
     openclaw config get gateway.auth.token
     ```

   - 在浏览器打开 `http://127.0.0.1:18789/`，点击右上角设置，把这个 token 粘贴到「Gateway Token」输入框保存；
   - 刷新页面，`Health` 应从 `Offline` 变为绿色 `Online`，`Status` 变为 `Connected`。

之后，无论你是打开 `http://localhost:18789/` 还是 `http://localhost:18789/overview`，只要浏览器里保存的 token 和 `gateway.auth.token` 一致，就可以正常使用，不再出现 1008 报错。

### 3.1 启动 / 停止 / 重启 / 状态

- **启动网关**

```bash
openclaw gateway start
```

- **停止网关**

```bash
openclaw gateway stop
```

- **重启网关**

> 修改 `memory.backend` 或其他关键配置后，必须重启网关才能生效。

```bash
openclaw gateway restart
```

- **查看网关状态**

```bash
openclaw gateway status
```

典型输出包括：

- 运行状态（running / stopped）；
- 日志路径；
- WebSocket 监听地址（如 `ws://127.0.0.1:18789`）。

### 3.2 日志与诊断

当网关无法启动或立即退出时，可以结合：

- `openclaw doctor --fix`
- 日志文件（例如 `/tmp/openclaw/openclaw-YYYY-MM-DD.log`）

来进一步排查。

---

## 四、Memory 相关命令（含 backend 切换与验证）

### 4.1 查看 Memory 状态（验证当前后端）

- **人类可读**

```bash
openclaw memory status
```

关键关注点：

- `Memory Search (main)`：当前 Agent 的 Memory 搜索配置；
- `Provider`: `openai`（Builtin）或 `qmd`（QMD）；
- 若包含 `Backend: builtin|qmd` 字段，则以该字段为准。

- **机器可读（JSON）**

```bash
openclaw memory status --json | jq -r '.[0].status.backend'
```

若当前 CLI 版本支持 `backend` 字段，则输出：

- `builtin` 或 `qmd`。

### 4.2 切换 Memory 后端（builtin ↔ qmd）

有两类方式：**CLI 配置命令** 和 **项目脚本/直接编辑**。

#### 方式一：使用 CLI 配置命令（配置已清理时可用）

> 需要确保 `~/.openclaw/openclaw.json` 已经通过 `openclaw doctor --fix` 清理，  
> 且不再包含旧 CLI 不认识的字段，否则 `config set` 会报 `Config invalid`。

```bash
# 切换到 Builtin
openclaw config set memory.backend builtin
openclaw gateway restart

# 切换到 QMD
openclaw config set memory.backend qmd
openclaw gateway restart
```

验证：

```bash
openclaw memory status
# 或
openclaw memory status --json | jq -r '.[0].status.backend'
```

#### 方式二：编辑配置文件 + 重启网关

直接编辑 `~/.openclaw/openclaw.json`：

```json
{
  "memory": {
    "backend": "builtin"
  }
}
```

或设置为 `"qmd"`，然后执行：

```bash
openclaw gateway restart
```

验证当前配置中的 backend：

```bash
jq -r '.memory.backend // "builtin"' ~/.openclaw/openclaw.json
```

#### 方式三：使用项目脚本（推荐，在本仓库内）

本仓库提供了一个不依赖 CLI 校验的脚本：`doc/scripts/memory-switch.sh`。

- **仅修改配置，不重启网关**

```bash
# 从项目根目录
bash doc/scripts/memory-switch.sh builtin
bash doc/scripts/memory-switch.sh qmd
```

- **修改配置并尝试重启网关**

```bash
bash doc/scripts/memory-switch.sh builtin --restart
bash doc/scripts/memory-switch.sh qmd --restart
```

脚本行为：

- 直接用 Python 修改 `~/.openclaw/openclaw.json` 中的 `memory.backend`；
- 若选择 `qmd` 且未找到 QMD 索引，会给出如何构建索引的提示；
- 末尾输出一行验证建议：

```bash
jq -r '.memory.backend // "builtin"' ~/.openclaw/openclaw.json
```

> 优点：即使某些 CLI 子命令因配置校验问题暂时不可用，脚本仍可可靠地切换 backend。

---

## 五、其他常见 CLI（按需补充）

根据你当前项目的使用情况，常见还会用到：

- **Agents / Sessions 相关**（如有启用）：
  - `openclaw agents list`
  - `openclaw sessions list`
- **调试 / 日志**：
  - `openclaw logs`（若有对应子命令）
  - 或直接查看 doctor 输出中给出的日志路径。

由于这些命令与 Memory 后端切换关系不大，此处不展开，你可以在 `doc/sum/OpenClaw功能总结.md` 中补充更细的功能级说明，本文件更偏向「CLI 命令速查 + Memory 相关用法」。

