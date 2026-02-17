#!/bin/bash
# =============================================================================
# Multi-Agents Verify Script for "Smart Shopper Protocol"
# 用于快速检查多 Agent 场景配置是否就绪（不依赖 openclaw CLI）：
#   1. 检查 openclaw.json 中是否存在 shop-hunter/shop-skeptic/shop-auditor；
#   2. 检查 shop-auditor 是否配置了 subagents.allowAgents；
#   3. 打印三个 Agent 的 workspace 路径和 AGENTS.md 是否存在；
#   4. 输出下一步建议：如何用 openclaw chat 挂到 shop-auditor 做业务验证。
#
# 用法：
#   bash scripts/multi-agents-verify.sh
# =============================================================================

set -euo pipefail

CONFIG_FILE="${OPENCLAW_CONFIG:-$HOME/.openclaw/openclaw.json}"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: 未找到 OpenClaw 配置文件："
  echo "  $CONFIG_FILE"
  echo "请先运行一次 openclaw（或 openclaw gateway start）生成默认配置，再重试。"
  exit 1
fi

echo "使用配置文件：$CONFIG_FILE"
echo ""

python3 - <<'PYCODE'
import json, os, pathlib

config_path = os.environ.get("OPENCLAW_CONFIG", os.path.join(os.path.expanduser("~"), ".openclaw", "openclaw.json"))

with open(config_path, "r", encoding="utf-8") as f:
    cfg = json.load(f)

agents_cfg = cfg.get("agents", {})
agent_list = agents_cfg.get("list", [])

ids = [a.get("id") for a in agent_list]
print("当前 agents.list 中的 id 列表：")
print("  ", ids)
print("")

required = ["shop-hunter", "shop-skeptic", "shop-auditor"]
missing = [r for r in required if r not in ids]
if missing:
    print("[FAIL] 缺少以下多 Agent 场景所需的 Agent：", missing)
    print("       请先运行 scripts/multi-agents-setup.sh 再重试。")
else:
    print("[OK] 三个多 Agent 已在 agents.list 中声明。")

print("")

auditor = next((a for a in agent_list if a.get("id") == "shop-auditor"), None)
if not auditor:
    print("[WARN] 未找到 shop-auditor 的详细配置，跳过 subagents 检查。")
else:
    subagents = auditor.get("subagents") or auditor.get("subAgents") or {}
    allow_agents = subagents.get("allowAgents")
    print("shop-auditor.subagents 配置：", subagents)
    if not allow_agents:
        print("[FAIL] shop-auditor.subagents.allowAgents 为空或缺失，")
        print("       无法通过 sessions_spawn 调用子 Agent。")
    else:
        print("[OK] shop-auditor.subagents.allowAgents =", allow_agents)

print("")

home = os.path.expanduser("~")
workspaces = {
    "shop-hunter":  os.path.join(home, ".openclaw", "workspace-shop-hunter"),
    "shop-skeptic": os.path.join(home, ".openclaw", "workspace-shop-skeptic"),
    "shop-auditor": os.path.join(home, ".openclaw", "workspace-shop-auditor"),
}

for aid, path in workspaces.items():
    p = pathlib.Path(path)
    agents_md = p / "AGENTS.md"
    print(f"{aid} workspace: {path}")
    if not p.exists():
        print(f"  [FAIL] 目录不存在，请确认是否已运行 multi-agents-setup.sh。")
    else:
        print(f"  [OK] 目录存在。")
    if not agents_md.exists():
        print(f"  [WARN] 缺少 {agents_md.name}，建议补充该 Agent 的角色说明。")
    else:
        print(f"  [OK] 存在 {agents_md.name}")
    print("")

print("验证完成。")
print("")
print("下一步建议：")
print("  1) 确保 openclaw gateway 已启动；")
print("  2) 在 openclaw chat 或控制台中选择 agentId=shop-auditor；")
print("  3) 发送类似指令：")
print('     「帮我按你们团队流程做一次 Sony WH-1000XM5 的全网比价和口碑避雷，')
print('       最后在桌面生成 Markdown 报告，并告诉我结论。」')
print("  4) 然后在本机终端执行：")
print("       ls ~/Desktop | grep buying_guide || echo '未找到 buying_guide 文件，请检查 Agent 输出或路径。'")

PYCODE

