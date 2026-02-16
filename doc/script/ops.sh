#!/bin/bash
# =============================================================================
# OpenClaw 运维脚本 (macOS)
# 用途: 日常运维操作快捷命令集合
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

OPENCLAW_SRC_DIR="${OPENCLAW_SRC_DIR:-$HOME/Documents/workspace/openclaw/openclaw-src}"

usage() {
    echo -e "${CYAN}OpenClaw 运维脚本${NC}"
    echo ""
    echo "用法: $0 <command>"
    echo ""
    echo "服务管理:"
    echo "  start           启动网关服务"
    echo "  stop            停止网关服务"
    echo "  restart         重启网关服务"
    echo "  status          查看完整状态"
    echo "  health          健康检查"
    echo "  logs            查看实时日志"
    echo ""
    echo "诊断与维护:"
    echo "  doctor          运行诊断检查"
    echo "  doctor-fix      运行诊断并自动修复"
    echo "  security        安全审计"
    echo ""
    echo "模型与通道:"
    echo "  model-status    查看模型状态"
    echo "  channel-status  查看通道状态"
    echo "  test-model      测试模型连通性"
    echo ""
    echo "版本管理:"
    echo "  update          更新到最新 tag 版本"
    echo "  version         查看当前版本"
    echo "  rebuild         重新构建"
    echo ""
    echo "其他:"
    echo "  dashboard       打开控制面板"
    echo "  config          查看当前配置"
    echo "  sessions        查看会话列表"
    echo "  backup          备份配置"
}

case "${1:-help}" in
    # ──────── 服务管理 ────────
    start)
        echo -e "${GREEN}启动网关...${NC}"
        openclaw gateway start
        sleep 3
        openclaw gateway status
        ;;
    stop)
        echo -e "${YELLOW}停止网关...${NC}"
        openclaw gateway stop
        ;;
    restart)
        echo -e "${YELLOW}重启网关...${NC}"
        openclaw gateway restart
        sleep 3
        openclaw gateway status
        ;;
    status)
        openclaw status
        ;;
    health)
        openclaw health
        ;;
    logs)
        openclaw logs --follow
        ;;

    # ──────── 诊断与维护 ────────
    doctor)
        openclaw doctor --non-interactive
        ;;
    doctor-fix)
        openclaw doctor --fix
        ;;
    security)
        openclaw security audit --deep
        ;;

    # ──────── 模型与通道 ────────
    model-status)
        openclaw models status
        ;;
    channel-status)
        openclaw channels status
        ;;
    test-model)
        echo -e "${CYAN}测试模型连通性...${NC}"
        openclaw agent --local --session-id "ops-test-$(date +%s)" \
            --message "回复OK确认收到" --json 2>&1 | \
            python3 -c "import sys,json; d=json.load(sys.stdin); print('模型响应:', d['payloads'][0]['text']); print('模型:', d['meta']['agentMeta']['model']); print('耗时:', d['meta']['durationMs'], 'ms')" 2>/dev/null || \
            openclaw agent --local --session-id "ops-test-$(date +%s)" --message "回复OK确认收到"
        ;;

    # ──────── 版本管理 ────────
    update)
        echo -e "${CYAN}更新 OpenClaw...${NC}"
        cd "$OPENCLAW_SRC_DIR"
        git fetch --tags
        LATEST_TAG=$(git describe --tags --abbrev=0 origin/main 2>/dev/null || git tag --sort=-v:refname | head -1)
        CURRENT_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "unknown")
        echo "当前版本: $CURRENT_TAG"
        echo "最新版本: $LATEST_TAG"
        if [ "$CURRENT_TAG" = "$LATEST_TAG" ]; then
            echo -e "${GREEN}已是最新版本${NC}"
            exit 0
        fi
        echo "更新到 $LATEST_TAG..."
        git checkout "$LATEST_TAG"
        SHARP_IGNORE_GLOBAL_LIBVIPS=1 pnpm install
        pnpm ui:build
        pnpm build
        pnpm link --global
        openclaw gateway restart || true
        echo -e "${GREEN}更新完成: $(openclaw --version)${NC}"
        ;;
    version)
        echo "OpenClaw: $(openclaw --version)"
        echo "Node.js: $(node -v)"
        echo "pnpm: $(pnpm -v)"
        echo "源码目录: $OPENCLAW_SRC_DIR"
        cd "$OPENCLAW_SRC_DIR" && echo "Git tag: $(git describe --tags --abbrev=0 2>/dev/null || echo 'N/A')"
        ;;
    rebuild)
        echo -e "${CYAN}重新构建...${NC}"
        cd "$OPENCLAW_SRC_DIR"
        SHARP_IGNORE_GLOBAL_LIBVIPS=1 pnpm install
        pnpm ui:build
        pnpm build
        echo -e "${GREEN}构建完成${NC}"
        openclaw gateway restart || true
        ;;

    # ──────── 其他 ────────
    dashboard)
        openclaw dashboard
        ;;
    config)
        cat ~/.openclaw/openclaw.json
        ;;
    sessions)
        openclaw sessions list 2>/dev/null || openclaw sessions
        ;;
    backup)
        BACKUP_DIR="$HOME/.openclaw-backup/$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$BACKUP_DIR"
        cp -r ~/.openclaw/openclaw.json "$BACKUP_DIR/" 2>/dev/null || true
        cp -r ~/.openclaw/agents "$BACKUP_DIR/" 2>/dev/null || true
        cp -r ~/.openclaw/credentials "$BACKUP_DIR/" 2>/dev/null || true
        echo -e "${GREEN}备份完成: $BACKUP_DIR${NC}"
        ls -la "$BACKUP_DIR"
        ;;

    help|--help|-h)
        usage
        ;;
    *)
        echo -e "${RED}未知命令: $1${NC}"
        usage
        exit 1
        ;;
esac
