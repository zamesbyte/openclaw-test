#!/bin/bash
# =============================================================================
# Multi-Agents Setup Script for "Smart Shopper Protocol"
# 在 OpenClaw 中为「全网比价与口碑避雷助手」场景创建三个协作 Agent：
#   - shop-hunter  : 赏金猎人（浏览器搜价）
#   - shop-skeptic : 鉴谎师   （全网查口碑）
#   - shop-auditor : 审计员   （汇总 + 写 Markdown 报告，兼 orchestrator）
#
# 作用：
#   1. 在 ~/.openclaw/openclaw.json 中追加/更新 agents.list 配置（若已存在则跳过同名条目）。
#   2. 为三个 Agent 创建各自 workspace 目录与基础 AGENTS.md，写入角色说明。
#   3. 为 shop-auditor 配置 subagents.allowAgents，使其可以通过 sessions_spawn 调用
#      shop-hunter 与 shop-skeptic。
#
# 不会做的事：
#   - 不修改 bindings（不影响你已有的通道路由）。
#   - 不启动或重启 gateway。
#
# 用法（从项目根或任意目录执行均可）：
#   bash scripts/multi-agents-setup.sh
#
# 执行完成后，你可以：
#   - 用 `openclaw agents list` 查看新增的三个 Agent；
#   - 在 openclaw chat / 控制台中指定 agentId=shop-auditor，与审计员对话；
#   - 让审计员按业务设计调用子 Agent 完成「全网比价 + 口碑避雷」任务。
# =============================================================================

set -euo pipefail

CONFIG_FILE="${OPENCLAW_CONFIG:-$HOME/.openclaw/openclaw.json}"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: OpenClaw config file not found:"
  echo "  $CONFIG_FILE"
  echo "请先运行一次 openclaw（或 openclaw gateway start）生成默认配置，再重试。"
  exit 1
fi

timestamp="$(date +%Y%m%d-%H%M%S)"
backup_file="${CONFIG_FILE}.bak-multi-agents-${timestamp}"

echo "备份配置文件到:"
echo "  $backup_file"
cp "$CONFIG_FILE" "$backup_file"

echo ""
echo "写入/更新 agents.list 以及 subagents 默认配置..."

python3 - <<'PYCODE'
import json, os, textwrap, pathlib

config_path = os.environ.get("OPENCLAW_CONFIG", os.path.join(os.path.expanduser("~"), ".openclaw", "openclaw.json"))

with open(config_path, "r", encoding="utf-8") as f:
    cfg = json.load(f)

agents = cfg.setdefault("agents", {})
agent_list = agents.setdefault("list", [])

def ensure_agent(agent_id, workspace, identity_name, emoji, role_note, tools_block=None, subagents_block=None):
    for a in agent_list:
        if a.get("id") == agent_id:
            # 已存在则不覆盖，只在缺失字段时做最小填充
            a.setdefault("workspace", workspace)
            identity = a.setdefault("identity", {})
            identity.setdefault("name", identity_name)
            identity.setdefault("emoji", emoji)
            if tools_block:
                t = a.setdefault("tools", {})
                for k, v in tools_block.items():
                    t.setdefault(k, v)
            if subagents_block:
                s = a.setdefault("subagents", {})
                for k, v in subagents_block.items():
                    s.setdefault(k, v)
            print(f"[SKIP] Agent {agent_id} 已存在，仅补充必需字段。")
            return

    entry = {
        "id": agent_id,
        "workspace": workspace,
        "identity": {
            "name": identity_name,
            "emoji": emoji,
        },
    }
    if tools_block:
        entry["tools"] = tools_block
    if subagents_block:
        entry["subagents"] = subagents_block
    agent_list.append(entry)
    print(f"[ADD] Agent {agent_id} 已添加。")


home = os.path.expanduser("~")

# 统一给三个 Agent 单独 workspace，便于写各自的 AGENTS.md / Skills / 本地文件
ws_hunter  = os.path.join(home, ".openclaw", "workspace-shop-hunter")
ws_skeptic = os.path.join(home, ".openclaw", "workspace-shop-skeptic")
ws_auditor = os.path.join(home, ".openclaw", "workspace-shop-auditor")

# Agent A：赏金猎人（Browser）
ensure_agent(
    agent_id="shop-hunter",
    workspace=ws_hunter,
    identity_name="赏金猎人 (The Hunter)",
    emoji="🕵️",
    role_note="专注浏览器搜价，不关心口碑，只输出价格和链接。",
    tools_block={
        # 偏 coding，但默认你会基于全局 tools 再做收紧；这里只做最小引导。
        "profile": "coding",
        "allow": ["browser"],
        "deny": ["group:runtime", "nodes", "cron", "gateway"],
    },
)

# Agent B：鉴谎师（Search）
ensure_agent(
    agent_id="shop-skeptic",
    workspace=ws_skeptic,
    identity_name="鉴谎师 (The Skeptic)",
    emoji="🧐",
    role_note="专注查口碑、黑历史和风险评估。",
    tools_block={
        "profile": "coding",
        "allow": ["group:web"],
        "deny": ["group:runtime", "browser", "nodes"],
    },
)

# Agent C：审计员（文件汇总 + orchestrator）
ensure_agent(
    agent_id="shop-auditor",
    workspace=ws_auditor,
    identity_name="审计员 (The Auditor)",
    emoji="📊",
    role_note="负责汇总 Smart Shopper 三方结果、计算推荐，并写 Markdown 报告。",
    tools_block={
        "profile": "coding",
        "allow": ["group:fs", "sessions_spawn", "sessions_history", "sessions_list"],
        "deny": ["browser", "nodes", "cron", "gateway"],
    },
    subagents_block={
        # 允许审计员通过 sessions_spawn 调用这两个子 Agent
        "allowAgents": ["shop-hunter", "shop-skeptic"],
    },
)

with open(config_path, "w", encoding="utf-8") as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"\n已写回配置文件: {config_path}")

# ---------------------------------------------------------------------------
# 为三个 Agent 创建基本 workspace 目录与 AGENTS.md（若不存在）
# ---------------------------------------------------------------------------

def ensure_workspace_with_agents_md(path, title, body):
    p = pathlib.Path(path)
    p.mkdir(parents=True, exist_ok=True)
    agents_md = p / "AGENTS.md"
    if agents_md.exists():
        print(f"[SKIP] 已存在: {agents_md}")
        return
    content = f"# {title}\n\n" + textwrap.dedent(body).lstrip()
    agents_md.write_text(content, encoding="utf-8")
    print(f"[WRITE] 创建 {agents_md}")

ensure_workspace_with_agents_md(
    ws_hunter,
    "赏金猎人 (The Hunter)",
    """
    你是「赏金猎人」，专门负责在各大电商网站上**寻找最低价**。

    - 你的任务：只关心「价格」「链接」「卖家名」，不做任何口碑判断。
    - 多使用浏览器工具（browser）完成搜索、筛选和信息提取，比如：
      - 打开 Amazon / eBay / 京东 / 淘宝等电商网站；
      - 搜索指定商品；
      - 记录前若干个最低价候选（平台 / 价格 / 卖家 / 链接）。
    - 输出尽量结构化（JSON / Markdown 表格），方便后续 Agent 使用。
    - 如果遇到验证码或无法访问，请描述问题并尝试简单重试，而不是卡死。
    """,
)

ensure_workspace_with_agents_md(
    ws_skeptic,
    "鉴谎师 (The Skeptic)",
    """
    你是「鉴谎师」，专门负责**查口碑、挖黑料、评估风险**。

    - 你的任务：拿到卖家名称或链接后，尽可能从 Reddit / 论坛 / 什么值得买 / 贴吧等位置
      搜索负面评价，例如「假货」「翻新」「售后拒保」「发二手当新品」等。
    - 偏向保守，如果存在较多严重负面，就打「高风险」标签。
    - 使用 web_search / web_fetch 等工具抓取文本，再进行总结和打分。
    - 输出对每个候选项的「风险等级」「主要证据」与简短理由。
    """,
)

ensure_workspace_with_agents_md(
    ws_auditor,
    "审计员 (The Auditor)",
    """
    你是「审计员」，负责**整合多个 Agent 的结果并做最终推荐**。

    - 你会收到：
      - 赏金猎人 (shop-hunter) 给出的价格列表（平台 / 价格 / 卖家 / 链接）。
      - 鉴谎师 (shop-skeptic) 给出的风险评估（每个卖家的风险等级与理由）。
    - 你的任务：
      1. 通过 sessions_spawn 调用「赏金猎人」与「鉴谎师」，获取价格列表与风险评估；
      2. 计算一个简单的「性价比」或「推荐等级」（综合价格与风险）；
      3. 生成一份 Markdown 报告，包含表格 + 清晰结论；
      4. 将报告写入本机某个固定路径（例如 ~/Desktop/buying_guide.md）。
    - 你是这个场景对用户的唯一入口：用户只需要和你对话，你负责调度其他 Agent。
    """,
)

PYCODE

echo ""
echo "完成多 Agent 基础配置。后续步骤建议："
echo "1) 使用 \`openclaw agents list\` 确认已存在 shop-hunter / shop-skeptic / shop-auditor。"
echo "2) 在 openclaw chat 或 Dashboard 中，将会话绑定到 agentId=shop-auditor，"
echo "   用自然语言给出商品名称，让其按设计调用子 Agent 完成『全网比价 + 口碑避雷』。"
echo ""
echo "如需进一步的业务验证步骤，请参考项目文档：doc/sum/多Agent全网比价助手实战.md"

