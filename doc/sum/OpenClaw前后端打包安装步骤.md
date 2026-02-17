# OpenClaw 前后端打包安装步骤

> 从 `openclaw-src` 源码完成后端 + Control UI 构建、打包并全局安装的完整执行步骤。  
> 适用场景：使用自构建版本（含最新代码或本地修改）、避免 Dashboard「Control UI assets not found」等路径不一致问题。

---

## 一、环境要求

- **Node.js**：≥ 22.12.0（见 `openclaw-src/package.json` 的 `engines.node`）
- **pnpm**：建议与项目一致（当前 `packageManager: "pnpm@10.23.0"`）
- 已克隆或拥有 **openclaw** 仓库，且 `openclaw-src` 目录存在

---

## 二、执行步骤概览

| 步骤 | 说明 |
|------|------|
| 1 | 进入源码目录并安装依赖 |
| 2 | 打包（自动执行后端构建 + Control UI 构建） |
| 3 | 全局安装生成的 tgz 包 |
| 4 | 若已有 Gateway 在运行，重启以使新安装生效 |
| 5 | 验证 CLI 与 Dashboard |

---

## 三、详细步骤

### 3.1 进入源码目录并安装依赖

```bash
cd /path/to/openclaw/openclaw-src
pnpm install
```

确保无报错；若有 lockfile 变更或首次克隆，此步会拉取全部依赖。

### 3.2 打包（后端 + Control UI 一并构建）

```bash
cd /path/to/openclaw/openclaw-src
pnpm pack
```

- **含义**：`pnpm pack` 会先执行 **prepack** 脚本（见 `package.json`），即：
  - `pnpm build` — 后端构建（tsdown、plugin-sdk、build-info 等），产物在 `dist/`
  - `pnpm ui:build` — Control UI 构建（Vite），产物在 `dist/control-ui/`
- **结果**：在当前目录生成 `openclaw-<version>.tgz`（例如 `openclaw-2026.2.12.tgz`）。该 tgz 内已包含 `dist/`（含 `control-ui`）、`openclaw.mjs`、文档与扩展等 `files` 字段声明内容。
- **耗时**：视机器而定，通常数十秒到数分钟。

若只需单独构建（不打包），可手动执行：

```bash
pnpm build        # 仅后端
pnpm ui:build     # 仅 Control UI（会写入 dist/control-ui）
```

### 3.3 全局安装

使用上一步生成的 tgz 进行全局安装（以版本 2026.2.12 为例，请按实际文件名替换）：

```bash
pnpm add -g ./openclaw-2026.2.12.tgz
```

- 路径可为相对路径（相对于当前工作目录）或绝对路径，例如：  
  `pnpm add -g /path/to/openclaw-src/openclaw-2026.2.12.tgz`
- 安装后 `openclaw` 命令指向此次安装；CLI、Gateway 与 Dashboard 使用的 Control UI 均来自同一包内 `dist/control-ui`。

**查看当前版本对应的 tgz 文件名：**

```bash
ls openclaw-*.tgz
# 或
cat package.json | grep '"version"'
```

### 3.4 若已有 Gateway 在运行：重启

若在本次安装之前已经启动了 Gateway（例如通过 LaunchAgent、systemd 或前台 `openclaw gateway`），**必须重启** Gateway 进程，新进程才会从新安装的目录解析 `dist/control-ui`，否则访问 Dashboard 仍可能返回 503「Control UI assets not found」。

```bash
openclaw gateway restart
```

若未安装过 Gateway 服务，可忽略此步；之后首次运行 `openclaw gateway` 时会使用新安装的包。

### 3.5 验证

1. **CLI 与版本**
   ```bash
   which openclaw
   openclaw --version
   ```
   应看到全局路径（如 `…/pnpm/openclaw`）和与 `package.json` 一致的版本号。

2. **Dashboard（Control UI）**
   - 启动 Gateway：`openclaw gateway`（或已通过服务启动）。
   - 在终端执行：`openclaw dashboard`，按提示在浏览器打开链接；或直接访问配置的 Gateway 端口（如 `http://127.0.0.1:18789/`）。
   - 应返回 200 和完整 HTML（含 `openclaw-app`、assets 等），而非 503 或「Control UI assets not found」。

3. **可选：本地 curl 快速检查**
   ```bash
   curl -sS -o /dev/null -w "%{http_code}" http://127.0.0.1:18789/
   ```
   期望输出 `200`。

---

## 四、一键脚本示例

在 **openclaw-src** 目录下可封装为一行或脚本，便于重复执行（版本号需与 `package.json` 一致或从 `package.json` 读取）：

```bash
cd /path/to/openclaw/openclaw-src
pnpm install && pnpm pack && pnpm add -g ./openclaw-2026.2.12.tgz
openclaw gateway restart   # 若已有 Gateway
openclaw --version && curl -sS -o /dev/null -w "Dashboard HTTP: %{http_code}\n" http://127.0.0.1:18789/
```

---

## 五、故障排查

| 现象 | 处理 |
|------|------|
| `pnpm pack` 报错（build/ui:build 失败） | 检查 Node 版本、`pnpm install` 是否成功；单独执行 `pnpm build` 与 `pnpm ui:build` 定位报错。 |
| 安装后 Dashboard 仍 503「Control UI assets not found」 | 多为未重启 Gateway；执行 `openclaw gateway restart`。若仍不行，确认全局安装目录下存在 `dist/control-ui/index.html`（如 `$(pnpm root -g)/openclaw/dist/control-ui/`）。 |
| 希望 Gateway 使用其他目录的 Control UI | 在配置中设置 `gateway.controlUi.root` 为包含 `index.html` 的目录绝对路径，然后重启 Gateway。 |
| 仅开发时临时用本地 UI、不重装包 | 在 openclaw-src 下执行 `pnpm ui:build`，并将 `gateway.controlUi.root` 指向 `openclaw-src/dist/control-ui`，或从 openclaw-src 启动 Gateway（如 `pnpm exec openclaw gateway`）。 |

---

## 六、相关文档

- [飞书发邮件到Gmail故障修复](./飞书发邮件到Gmail故障修复.md) — Dashboard 与 Control UI 相关说明、打包安装简述
- [Gmail配置为OpenClaw专属Channel](./Gmail配置为OpenClaw专属Channel.md) — 配置与渠道
- 官方文档：Control UI / 安装与更新（见 openclaw-src 仓库内 `docs/`）
