#!/bin/bash
# =============================================================================
# OpenClaw 源码安装脚本 (macOS)
# 版本: v2026.2.12
# 日期: 2026-02-13
# 用途: 基于源码一键安装 OpenClaw，包含环境检查、构建、全局链接
# =============================================================================

set -euo pipefail

# ──────────────────────── 配置区 ────────────────────────
OPENCLAW_SRC_DIR="${OPENCLAW_SRC_DIR:-$HOME/Documents/workspace/openclaw/openclaw-src}"
OPENCLAW_TAG="${OPENCLAW_TAG:-}"  # 留空则使用最新 tag
MIN_NODE_VERSION=22
# ────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()   { echo -e "${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[✗]${NC} $*"; exit 1; }

# ──────────────── 1. 环境检查 ────────────────
echo "=========================================="
echo "  OpenClaw 源码安装脚本 (macOS)"
echo "=========================================="
echo ""

# 检查 Node.js
if ! command -v node &>/dev/null; then
    error "Node.js 未安装。请先安装 Node.js >= $MIN_NODE_VERSION (推荐 nvm 或 Homebrew)"
fi

NODE_MAJOR=$(node -v | sed 's/v//' | cut -d'.' -f1)
if [ "$NODE_MAJOR" -lt "$MIN_NODE_VERSION" ]; then
    error "Node.js 版本过低 (当前: $(node -v))，需要 >= $MIN_NODE_VERSION"
fi
log "Node.js $(node -v)"

# 检查 pnpm
if ! command -v pnpm &>/dev/null; then
    warn "pnpm 未安装，正在安装..."
    npm install -g pnpm
fi
log "pnpm $(pnpm -v)"

# 检查 Git
if ! command -v git &>/dev/null; then
    error "Git 未安装。请先安装 Git"
fi
log "Git $(git --version | awk '{print $3}')"

# ──────────────── 2. 获取源码 ────────────────
if [ ! -d "$OPENCLAW_SRC_DIR" ]; then
    warn "源码目录不存在，正在克隆..."
    git clone https://github.com/openclaw/openclaw.git "$OPENCLAW_SRC_DIR"
fi

cd "$OPENCLAW_SRC_DIR"
log "源码目录: $OPENCLAW_SRC_DIR"

# ──────────────── 3. 切换到指定版本 ────────────────
if [ -z "$OPENCLAW_TAG" ]; then
    OPENCLAW_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "main")
fi

git fetch --tags 2>/dev/null || true
git checkout "$OPENCLAW_TAG" 2>/dev/null
log "版本: $OPENCLAW_TAG"

# ──────────────── 4. 安装依赖 ────────────────
log "安装依赖..."
SHARP_IGNORE_GLOBAL_LIBVIPS=1 pnpm install

# ──────────────── 5. 构建 ────────────────
log "构建 UI..."
pnpm ui:build

log "构建主项目..."
pnpm build

# ──────────────── 6. 全局链接 ────────────────
log "全局链接 CLI..."
pnpm link --global 2>/dev/null || true

# ──────────────── 7. 验证安装 ────────────────
if command -v openclaw &>/dev/null; then
    log "安装成功: openclaw $(openclaw --version)"
else
    error "安装失败: openclaw 命令未找到。请检查 PATH 是否包含 pnpm 全局 bin 目录"
fi

# ──────────────── 8. 初始化目录 ────────────────
mkdir -p ~/.openclaw/agents/main/sessions
mkdir -p ~/.openclaw/credentials
chmod 700 ~/.openclaw
chmod 700 ~/.openclaw/credentials 2>/dev/null || true
log "状态目录已初始化"

# ──────────────── 9. 健康检查 ────────────────
log "运行 doctor 检查..."
openclaw doctor --non-interactive || true

echo ""
echo "=========================================="
echo "  安装完成!"
echo "  版本: $(openclaw --version)"
echo "  下一步:"
echo "    1. 编辑配置: ~/.openclaw/openclaw.json"
echo "    2. 安装服务: openclaw gateway install"
echo "    3. 启动网关: openclaw gateway start"
echo "    4. 查看状态: openclaw status"
echo "=========================================="
