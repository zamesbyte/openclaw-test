# 多 Agent 脚本写入 `subagents` 默认字段导致 Config invalid 的修复记录

> 时间：2026-02-17  
> 相关文件：`scripts/multi-agents-setup.sh`, `~/.openclaw/openclaw.json`

---

## 问题现象

在运行多 Agent 初始化脚本：

```bash
bash scripts/multi-agents-setup.sh
openclaw agents list
```

时，`openclaw agents list` 报错：

```text
Config invalid at ~/.openclaw/openclaw.json
Problem:
  - agents.defaults.subagents: Unrecognized keys: "maxSpawnDepth", "maxChildrenPerAgent"

Run: openclaw doctor --fix
```

说明当前本机安装的 OpenClaw 版本的配置 schema 中，`agents.defaults.subagents` 还不支持 `maxSpawnDepth`、`maxChildrenPerAgent` 这两个字段。

---

## 触发原因

早期版本的 `scripts/multi-agents-setup.sh` 在写入多 Agent 配置时，会无条件追加：

```json5
agents.defaults.subagents.maxSpawnDepth
agents.defaults.subagents.maxChildrenPerAgent
agents.defaults.subagents.maxConcurrent
```

其中 `maxSpawnDepth`、`maxChildrenPerAgent` 在当前 OpenClaw 版本中尚未被 schema 识别，导致后续任何依赖配置校验的 CLI（如 `openclaw agents list`）都报 Config invalid。

---

## 修复方案

1. **使用 doctor 清理已写入的不兼容字段**

   在命令行执行：

   ```bash
   openclaw doctor --fix
   ```

   doctor 会检测到未知字段并从 `~/.openclaw/openclaw.json` 中移除：

   - `agents.defaults.subagents.maxSpawnDepth`
   - `agents.defaults.subagents.maxChildrenPerAgent`

   清理后再次执行：

   ```bash
   openclaw agents list
   ```

   可以正常列出多 Agent（`shop-hunter` / `shop-skeptic` / `shop-auditor`），说明配置恢复合法。

2. **修改初始化脚本，避免后续再次写入不兼容字段**

   更新 `scripts/multi-agents-setup.sh`，移除自动写入 `agents.defaults.subagents.*` 默认值的逻辑，仅保留：

   - `agents.list` 三个 Agent 的配置；
   - `shop-auditor.subagents.allowAgents = ["shop-hunter", "shop-skeptic"]`；
   - 三个 workspace 与 `AGENTS.md` 的创建。

   这样，脚本不会再往当前版本不支持的 `subagents` 字段写入未知 key，避免未来再次触发 Config invalid。

---

## 修复后验证

1. 重新运行脚本（不会再引入非法字段，只是补充 Agent 配置）：  

   ```bash
   cd /Users/zhanlifeng/Documents/workspace/openclaw
   bash scripts/multi-agents-setup.sh
   ```

2. 使用验证脚本检查多 Agent 配置与 workspace：

   ```bash
   bash scripts/multi-agents-verify.sh
   ```

   预期输出包括：

   - `shop-hunter` / `shop-skeptic` / `shop-auditor` 三个 Agent 已在 `agents.list` 中；
   - `shop-auditor.subagents.allowAgents = ['shop-hunter', 'shop-skeptic']`；
   - 三个 workspace 目录和各自的 `AGENTS.md` 均存在。

3. 使用 CLI 再次确认：

   ```bash
   openclaw agents list
   ```

   能正常输出各 Agent 信息且不再有 Config invalid 报错。

---

## 影响评估

- **对多 Agent 场景本身**：  
  - 三个 Agent 的核心配置（id / workspace / tools / subagents.allowAgents）不受影响；
  - 多 Agent Smart Shopper 场景可正常运行。

- **对全局配置的影响**：  
  - doctor 仅移除了当前版本 schema 不认识的 `subagents` 字段，不会波及其他配置项；
  - 新版本 `scripts/multi-agents-setup.sh` 不再写入这些字段，因此后续不会重复触发类似报错。

如后续升级到支持 `agents.defaults.subagents.*` 全量字段的 OpenClaw 版本，可再按新版本文档手动补充这些默认值。当前版本下保持脚本「只写受支持字段」是更稳妥的选择。  

