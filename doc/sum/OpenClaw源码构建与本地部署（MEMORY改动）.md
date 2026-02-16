## OpenClaw 源码构建与本地部署（MEMORY 改动版）

> 面向「完全小白」的操作说明：  
> 以这次你在 `openclaw-src` 里对 MEMORY 相关 `.ts` 文件的改动为例，讲清楚：  
> 1. 我是如何**从源码重新构建** OpenClaw；  
> 2. 如何在本地**使用新的构建结果**；  
> 3. 这些步骤与你现在看到的 `~/.openclaw` 目录结构、`SOUL.md` 的位置有什么关系。

---

## 一、几个重要目录先搞清楚

先区分三个完全不同的目录：

- **1）源码目录（你正在改的）**

  ```text
  /Users/zhanlifeng/Documents/workspace/openclaw/
    └─ openclaw-src/
        ├─ src/           # TypeScript 源码（包括 MEMORY 相关 ts）
        ├─ dist/          # 构建后的 JS 文件（pnpm build 生成）
        ├─ docs/          # 官方文档
        ├─ docs/zh-CN/reference/templates/SOUL.md   # SOUL 模板
        ├─ package.json   # 构建与打包入口
        └─ ...
  ```

- **2）运行时数据目录（截图里的结构）**

  ```text
  ~/.openclaw/
    ├─ openclaw.json   # 主配置文件
    ├─ agents/         # Agent 配置、会话数据
    ├─ workspace/      # 工作区（AGENTS.md、SOUL.md 等）
    ├─ logs/           # 日志
    ├─ memory/         # 默认 MEMORY.md / memory/*.md 所在
    └─ ...
  ```

  截图中的树形结构描述的就是 **这个目录**，和源码目录 `openclaw-src` 并不是一回事。

- **3）系统里的全局 openclaw 可执行文件**

  ```bash
  which openclaw
  # 一般是 /usr/local/bin/openclaw 或 pnpm 全局目录里的可执行文件
  ```

  这个「全局 CLI」就是你在终端里直接敲 `openclaw ...` 时实际运行的程序。  
  它 **可能来自 npm 官方发布版**，并不一定就是你当前 `openclaw-src` 目录里这份源码构建出来的版本。

理解这一点非常关键：  
你在 `openclaw-src/src/...` 改的 TypeScript，只会影响 **你之后从这个源码做的构建**；  
不会**自动**影响已经安装在系统里的 `openclaw` 命令。

---

## 二、从源码重新构建 OpenClaw（基于你改过的 MEMORY ts）

### 2.1 前置条件检查

1. **Node 版本**

   在 `openclaw-src/package.json` 里写着：

   ```json
   "engines": { "node": ">=22.12.0" }
   ```

   在终端里确认：

   ```bash
   node -v
   # 建议是 v22.12.0 或更新版本
   ```

2. **包管理工具：pnpm**

   `package.json` 中：

   ```json
   "packageManager": "pnpm@10.23.0"
   ```

   建议安装一次 pnpm：

   ```bash
   corepack enable
   corepack prepare pnpm@10.23.0 --activate
   pnpm -v   # 确认版本接近 10.x
   ```

### 2.2 安装依赖（第一次在这台机子上构建时需要）

在终端进入源码目录：

```bash
cd /Users/zhanlifeng/Documents/workspace/openclaw/openclaw-src
pnpm install
```

只要依赖没有重大变化，这一步后面可以不再重复。

### 2.3 构建（把 TypeScript 编译成 JS）

`package.json` 中的构建脚本：

```json
"scripts": {
  "build": "pnpm canvas:a2ui:bundle && tsdown && pnpm build:plugin-sdk:dts && node --import tsx scripts/write-plugin-sdk-entry-dts.ts && node --import tsx scripts/canvas-a2ui-copy.ts && node --import tsx scripts/copy-hook-metadata.ts && node --import tsx scripts/write-build-info.ts && node --import tsx scripts/write-cli-compat.ts",
  ...
}
```

你只需要执行：

```bash
cd /Users/zhanlifeng/Documents/workspace/openclaw/openclaw-src
pnpm build
```

这一步会完成：

- 把 `src/` 下的 TypeScript（包括你改过的 MEMORY 相关 ts）编译到 `dist/`；
- 生成 CLI 入口 `openclaw.mjs` 等文件；
- 写入一些构建信息（版本号、兼容性元数据等）。

**验证构建成功的小方法：**

- 查看 `dist/` 目录时间戳是否更新；
- 打印版本信息（后面用「本地运行」的方式验证）。

---

## 三、在本地使用你刚构建的版本（不覆盖全局安装）

很多时候，你只想在本机验证「新改的 MEMORY 逻辑」是不是正确，**不一定要立刻替换系统里的全局 `openclaw`**。  
这时推荐使用 **「本地运行」** 模式。

### 3.1 使用脚本本地运行 CLI

在 `openclaw-src/package.json` 中，有：

```json
"scripts": {
  "openclaw": "node scripts/run-node.mjs",
  "start": "node scripts/run-node.mjs",
  ...
}
```

你可以这样运行本地版本：

```bash
cd /Users/zhanlifeng/Documents/workspace/openclaw/openclaw-src
pnpm openclaw -- --version
```

解释：

- `pnpm openclaw` 会执行 `node scripts/run-node.mjs`；
- `--` 后面的参数会透传给脚本，相当于在当前源码目录下运行「开发版」的 `openclaw`。

示例（假设要用本地版本跑 memory 相关命令）：

```bash
cd /Users/zhanlifeng/Documents/workspace/openclaw/openclaw-src

# 查看配置
pnpm openclaw -- config print

# 查看 Memory 状态
pnpm openclaw -- memory status

# 用本地版本执行 agent
pnpm openclaw -- agent --agent main --local --message "测试 MEMORY 改动是否生效" --json
```

此时：

- 运行代码使用的是你刚才 `pnpm build` 生成的 `dist/`；
- 使用的运行时数据仍然是 `~/.openclaw`（同一套配置与 MEMORY 文件），所以「行为环境」和全局 `openclaw` 一致，只是代码版本不同。

> 小结：这是 **最安全** 的验证方式 —— 不动系统全局安装，改动只在当前源码树生效。

---

## 四、把构建好的版本安装为系统全局 `openclaw`（可选）

如果你希望：

- 在任何目录下敲 `openclaw ...` 时，都使用你改过并构建好的版本；

可以考虑把 `openclaw-src` 打成包，再装成全局 CLI。

### 4.1 打包为 npm tarball

在 `openclaw-src` 目录下执行：

```bash
cd /Users/zhanlifeng/Documents/workspace/openclaw/openclaw-src
pnpm pack
```

成功后，会在当前目录生成一个类似：

```text
openclaw-2026.2.12.tgz
```

### 4.2 全局安装这个 tarball

（以下以 pnpm 为例）：

```bash
# 可选：先卸载旧的全局 openclaw
pnpm remove -g openclaw

# 安装你刚打的包
pnpm add -g ./openclaw-2026.2.12.tgz
```

验证：

```bash
which openclaw
openclaw --version
```

- `which openclaw` 应该指向 pnpm 的全局 bin 目录；
- `openclaw --version` 显示的版本应与你的 `package.json` 中 `version` 一致（例如 `2026.2.12`）。

此时，你在任何终端目录下使用的 `openclaw`，就是**基于你改过的源码构建出来的版本**了。

---

## 五、这次实际做了什么 & 文档是怎么写到 `doc/sum` 的

结合你这次的需求，整个流程可以理解为：

1. **在源码中修改 MEMORY 相关 ts**

   例如：

   - `openclaw-src/src/config/zod-schema.agent-runtime.ts` 中加入 `query.rerank` 的 schema 定义；
   - `openclaw-src/src/memory/manager.ts` 中集成 `applyRerank()`；
   - `openclaw-src/src/memory/reranker.ts` 新增调用百炼 `gte-rerank` 的封装；
   - 等。

2. **在本地环境中构建 & 运行进行验证**

   参考本文件第 2、3 节：

   - 在 `openclaw-src` 下执行一次 `pnpm build`；
   - 通过 `pnpm openclaw -- memory status` / `pnpm openclaw -- agent ...` 等命令，在不影响全局安装的前提下验证新逻辑。

   （注意：你当前机器上的系统全局 `openclaw` 仍然是官方发布版，因此我们在修复 CLI 报错问题时，采用的是「清理配置 + 脚本切换 backend」的路线，而不是立刻替换全局 CLI。）

3. **把原理 / 步骤 / 验证过程写成文档**

   所有和 MEMORY 相关的说明，按你之前的要求，写到了 `doc/sum` 目录下，例如：

   - `MEMORY机制实现原理.md`：详细解释 BM25 / 向量 / Rerank、Builtin 与 QMD 管线；
   - `MEMORY机制总结.md`：从架构和配置角度总结两种后端与性能对比；
   - `MEMORY默认机制与切换验证.md`：说明默认是 builtin，如何切换、如何用 CLI 和对话验证；
   - `MEMORY机制总览与验证实践.md`：把上面三份再整合成一篇总览 + 实际验证记录；
   - **本文件**：`OpenClaw源码构建与本地部署（MEMORY改动）.md`，专门面向小白说明「改代码 → 构建 → 本地使用」这一段。

写的方式基本是：

```bash
# 在 doc/sum 目录下新增或编辑 md 文件
cd /Users/zhanlifeng/Documents/workspace/openclaw/doc/sum
# 使用编辑器/IDE 直接打开并修改
```

---

## 六、关于截图里的目录结构 & SOUL.md 的位置

你提到的截图类似这样：

```text
~/.openclaw/
├─ openclaw.json       # 主配置文件
├─ agents/             # Agent 配置和会话数据
│  └─ main/
│     ├─ agent/
│     └─ sessions/
├─ credentials/        # OAuth/Token 凭据
├─ workspace/          # 工作区（AGENTS.md, SOUL.md 等）
├─ skills/             # 共享技能
├─ hooks/              # 共享钩子
├─ logs/               # 日志
├─ cron/               # 定时任务数据
└─ memory/             # 记忆文件
```

这张图展示的是 **运行时数据目录 `~/.openclaw` 的结构**，而不是 `openclaw-src` 的源码结构。所以两者看上去不一样是正常的：

- `openclaw-src`：一个 npm 包/应用的源码仓库（有 `src/、dist/、docs/、apps/…`）；
- `~/.openclaw`：这个应用运行时在你电脑上落地的数据（配置、日志、工作区等）。

### 6.1 SOUL.md 现在在哪里？

从实际运行的 `openclaw agent` 日志可以看到，它注入的文件里有：

```text
/Users/zhanlifeng/.openclaw/workspace/SOUL.md
```

也就是说：

- **运行时真正使用的 `SOUL.md` 在：**

  ```text
  ~/.openclaw/workspace/SOUL.md
  ```

- 在源码仓库中，还有两份 **模板**：

  ```text
  openclaw-src/docs/reference/templates/SOUL.md
  openclaw-src/docs/zh-CN/reference/templates/SOUL.md
  ```

  OpenClaw 在第一次初始化时，会根据这些模板生成 `~/.openclaw/workspace/SOUL.md`（英文或中文版本），以后你编辑的就是这份运行时的 SOUL。

> 总结：  
> - 模板 SOUL 在 `openclaw-src/docs/.../SOUL.md`；  
> - 真正被 agent 使用的 SOUL 在 `~/.openclaw/workspace/SOUL.md`；  
> - 截图的目录结构描述的是 `~/.openclaw` 这一块，与源码目录结构不一致是正常也是必要的（一个是代码仓库，一个是运行数据）。

---

如果你希望，我可以再帮你补一小节「推荐日常开发流」到本文件最后，比如：  
「改 MEMORY ts → `pnpm build` → 用 `pnpm openclaw -- memory status/agent` 验证 → 若稳定再选择是否替换全局 `openclaw`」，让你以后每次改代码都按这条标准流程来。 

