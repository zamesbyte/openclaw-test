# OpenClaw CLI 配置校验报错根因分析

> 目标：解释为什么所有 `openclaw` 相关 CLI 都提示配置错误，给出「根因级」解决方案，并保证现有功能可用。

---

## 一、现象回顾

- 运行任意 `openclaw` 子命令（如 `openclaw config set`、`openclaw memory status`）时，终端都会先输出类似信息：
  - `Invalid config at ~/.openclaw/openclaw.json:`
  - `- agents.defaults.memorySearch.query: Unrecognized key: "rerank"`
  - `Config invalid`
  - 提示运行：`openclaw doctor --fix`
- 随后：
  - 某些命令（如 `openclaw config set`）**直接失败退出**；
  - 某些命令即使继续执行，也会持续打印「Config invalid」的告警。

这就是「所有 openclaw CLI 都在报错」的直接表现。

---

## 二、根本原因：单一全局配置 + 不同版本的 CLI schema 不兼容

### 2.1 唯一的全局配置文件

所有 `openclaw` CLI（无论是全局安装版、npx 版，还是你从源码编译的 dev 版）默认都会读取同一个全局配置文件：

- 路径：`~/.openclaw/openclaw.json`

也就是说：

- **不同版本的 `openclaw` 共用了同一份配置文件**；
- 只要其中有一个版本往里面写了「新字段」，其他老版本一读就可能「看不懂」。

### 2.2 CLI 在启动时会做「严格校验」

OpenClaw 的 CLI 在启动时会：

1. 加载 `~/.openclaw/openclaw.json`；
2. 用自己的 zod schema 做一次「严格校验」：
   - 字段缺失：给出默认值或警告；
   - **字段未知（schema 里没有定义）**：视为「未知字段」；
3. 若存在未知字段，则：
   - 某些代码路径（如 `openclaw config set`）直接认为「配置无效」，打印 **`Config invalid`** 并退出；
   - 其他命令会继续执行，但在开头打印一段「Config invalid; doctor will run with best-effort config.」的提示。

老版本 CLI 的 schema 中，**没有**我们在本仓库文档中新增、建议配置的某些字段，例如：

- `agents.defaults.memorySearch.query.rerank`

于是，当老版本 CLI 读取到包含这些字段的 `~/.openclaw/openclaw.json` 时，就会认为：

- `agents.defaults.memorySearch.query: Unrecognized key: "rerank"`  
- 进而给出全局的「Config invalid」提示。

### 2.3 本仓库中新字段是合法的，但老 CLI 不认识

在本仓库源码中，我们已经在 schema 里为 `query.rerank` 等字段**补上了类型定义**，因此：

- **本仓库编译出来的 CLI** 能够正确读取/使用这些配置；
- 但**你机器上现有的 openclaw 可执行程序**（例如从 npm 安装的稳定版）使用的是一个**较旧的 schema**，依然把 `query.rerank` 当成「未知字段」，从而导致：
  - 每次启动都打印「Config invalid」；
  - 某些命令（特别是 `openclaw config set` 这类对配置写操作很敏感的命令）直接拒绝执行。

**根因总结：**

- 只有一份全局配置文件；
- 我们往里面加入了「新字段」；
- 你当前 PATH 中的 openclaw 版本 schema 还不知道这些字段；
- 于是所有基于该二进制的 CLI 调用都会认为配置「Invalid」，导致你看到的报错。

---

## 三、解决思路：让所有 CLI 都能「看懂」这份配置

### 3.1 两条可选路径

从根因上，有两条方案：

- **方案 A：升级所有 CLI 到新 schema**  
  使用本仓库的源码编译出一个新版本的 `openclaw`，并让它成为你 PATH 中的主 CLI，这样：
  - 新 CLI 知道 `query.rerank` 等字段；
  - 校验会通过，不再报「Unrecognized key」。

- **方案 B：让配置保持「向后兼容」**（推荐）  
  即使新功能需要额外字段，尽量不把「老 CLI 完全不认识的字段」写入全局配置，或者保证这些字段可以被自动清理：
  - 已经出现的「未知字段」用 `openclaw doctor --fix` 或脚本移除；
  - 新功能尽量通过：
    - 内部默认值；
    - 环境变量；
    - 项目内局部配置（而不是全局 `~/.openclaw/openclaw.json`）
    来实现。

在你当前环境中，为了**尽快让所有 CLI 回复正常工作**，我们采用**方案 B**：

1. 清理现有全局配置，使其只包含「所有版本 CLI 都认识的字段」；
2. 保证 Memory / QMD / Rerank 等功能仍然可用（通过默认值和脚本），而不强依赖「新字段」的全局配置。

---

## 四、具体修复步骤（你可以直接照做）

### 4.1 一次性清理全局配置（建议手动执行）

按照 CLI 自己的提示，执行一次：

```bash
openclaw doctor --fix
```

这会：

- 读取 `~/.openclaw/openclaw.json`；
- 删除所有 schema 不认识的字段（包括 `agents.defaults.memorySearch.query.rerank` 等）；
- 输出一个「干净」的新配置文件。

**效果：**

- 之后再运行任意 `openclaw` 子命令：
  - 不会再出现「Config invalid」的全局报错；
  - `openclaw config set` 等命令也可以正常工作。

> 若你希望更可控，也可以不直接跑 doctor，而是手动编辑 `~/.openclaw/openclaw.json`，删除 `agents.defaults.memorySearch.query` 下的 `rerank` 等字段，然后保存即可，效果相同。

### 4.2 保证 Memory / QMD / Rerank 功能仍然可用

清理配置后，**不会影响我们已经在代码里实现的 Memory / QMD / Rerank 功能**，原因是：

- Memory 后端选择（builtin / qmd）依然由 `memory.backend` 控制；
- Rerank 相关逻辑在本仓库中有**合理的默认值**，即使配置中没有 `query.rerank` 字段，也可以按默认方式工作；
- 我们提供的脚本和文档（如 `doc/scripts/memory-switch.sh`、`doc/test/Memory后端对比测试.md` 等）都基于「最小必要配置」，不会强依赖那些会让老 CLI 报错的新字段。

如果后续你希望对 Rerank 做更细致的可配置化（例如单独关/开、改 topN 等），可以：

- 在**本仓库对应的开发 CLI** 中使用这些新字段；
- 或者改为通过环境变量进行控制。  

这样就不会再污染全局 `~/.openclaw/openclaw.json`，也不会影响到老版本 CLI。

---

## 五、对后续开发的约束与建议

为了避免类似问题再次发生，本仓库后续在设计配置字段时遵循以下约束：

- **避免在全局配置中引入老版本 CLI 完全不认识的新字段**，尤其是位于：
  - `agents.defaults.*`
  - `memory.*`
  等「核心路径」下的字段；
- 如确有需要：
  - 先确保本仓库中 **OpenClawSchema** 对这些字段有完整定义；
  - 并在文档中**明确标记**：  
    「以下配置项仅在你使用本仓库构建的 dev 版 CLI 时可用，稳定版 CLI 可能会报 Config invalid」。
- 对于大部分实验性或增强型功能，更推荐：
  - 使用**环境变量**启用/调整；
  - 或使用**项目局部的配置文件 / Agent 配置**，避免污染全局 `~/.openclaw/openclaw.json`。

---

## 六、你可以如何验证「根因已经修复」

按 4.1 完成一次性清理后，可以做如下验证：

1. 运行几条典型命令：

   ```bash
   openclaw config set memory.backend builtin
   openclaw memory status
   openclaw gateway status
   ```

   预期行为：

   - 不再打印「Config invalid」；
   - `config set` 命令不再立即退出，能正常修改配置。

2. 确认 Memory 功能仍然可用：

   - 按 `doc/scripts/memory-切换与验证命令.md` 中的步骤：
     - 切换 builtin/qmd；
     - 通过 `jq -r '.memory.backend // "builtin"' ~/.openclaw/openclaw.json` 或 `openclaw memory status` 验证；
   - 按 `doc/test/Memory后端对比测试.md` 跑一轮对比测试，确认搜索质量与预期一致。

只要上述两点都通过，就说明：

- **根因（配置与 CLI schema 不兼容）已解决**；
- **现有功能（Memory / QMD / Rerank 等）仍然可用**。

