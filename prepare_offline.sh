#!/bin/bash

# ==============================================
# 离线资源准备脚本
# 功能：预下载所有需要的网络资源
# ==============================================

set -e

# 颜色设置
RED=$(printf '\033[31m')
GREEN=$(printf '\033[32m')
YELLOW=$(printf '\033[33m')
BLUE=$(printf '\033[34m')
RESET=$(printf '\033[m')

echo "================================================================"
echo "  📦 开始下载离线安装资源"
echo "================================================================"
echo ""

# 创建离线资源目录
OFFLINE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/offline_resources"
mkdir -p "$OFFLINE_DIR"

echo "${BLUE}[1/4]${RESET} 下载Starship安装脚本..."
if [ -f "$OFFLINE_DIR/starship_install.sh" ]; then
    echo "  → 已存在，跳过"
else
    curl -sS https://starship.rs/install.sh -o "$OFFLINE_DIR/starship_install.sh"
    chmod +x "$OFFLINE_DIR/starship_install.sh"
    echo "  ${GREEN}✓ 下载完成${RESET}"
fi

echo ""
echo "${BLUE}[2/4]${RESET} 下载Starship二进制文件（预缓存）..."
# 获取最新版本号
STARSHIP_VERSION=$(curl -s https://api.github.com/repos/starship/starship/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
if [ -z "$STARSHIP_VERSION" ]; then
    echo "  ${YELLOW}⚠ 无法获取版本号，跳过${RESET}"
else
    echo "  → 最新版本: v${STARSHIP_VERSION}"
    STARSHIP_URL="https://github.com/starship/starship/releases/download/v${STARSHIP_VERSION}/starship-x86_64-unknown-linux-gnu.tar.gz"

    if [ -f "$OFFLINE_DIR/starship-x86_64-unknown-linux-gnu.tar.gz" ]; then
        echo "  → 已存在，跳过"
    else
        wget "$STARSHIP_URL" -O "$OFFLINE_DIR/starship-x86_64-unknown-linux-gnu.tar.gz" || {
            echo "  ${YELLOW}⚠ 下载失败，将使用在线安装${RESET}"
        }
        if [ -f "$OFFLINE_DIR/starship-x86_64-unknown-linux-gnu.tar.gz" ]; then
            echo "  ${GREEN}✓ 下载完成${RESET}"
        fi
    fi
fi

echo ""
echo "${BLUE}[3/4]${RESET} 克隆zsh-autosuggestions插件..."
if [ -d "$OFFLINE_DIR/zsh-autosuggestions" ]; then
    echo "  → 已存在，更新中..."
    cd "$OFFLINE_DIR/zsh-autosuggestions"
    git pull --depth=1
    cd - > /dev/null
    echo "  ${GREEN}✓ 更新完成${RESET}"
else
    git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions "$OFFLINE_DIR/zsh-autosuggestions"
    echo "  ${GREEN}✓ 克隆完成${RESET}"
fi

echo ""
echo "${BLUE}[4/6]${RESET} 克隆zsh-syntax-highlighting插件..."
if [ -d "$OFFLINE_DIR/zsh-syntax-highlighting" ]; then
    echo "  → 已存在，更新中..."
    cd "$OFFLINE_DIR/zsh-syntax-highlighting"
    git pull --depth=1
    cd - > /dev/null
    echo "  ${GREEN}✓ 更新完成${RESET}"
else
    git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting "$OFFLINE_DIR/zsh-syntax-highlighting"
    echo "  ${GREEN}✓ 克隆完成${RESET}"
fi

echo ""
echo "${BLUE}[5/6]${RESET} 克隆vim配置..."
if [ -d "$OFFLINE_DIR/vim" ]; then
    echo "  → 已存在，更新中..."
    cd "$OFFLINE_DIR/vim"
    git pull
    cd - > /dev/null
    echo "  ${GREEN}✓ 更新完成${RESET}"
else
    git clone https://gitee.com/hzx_3/vim.git "$OFFLINE_DIR/vim"
    echo "  ${GREEN}✓ 克隆完成${RESET}"
fi

echo ""
echo "${BLUE}[6/6]${RESET} 克隆Vundle插件管理器..."
if [ -d "$OFFLINE_DIR/vundle" ]; then
    echo "  → 已存在，更新中..."
    cd "$OFFLINE_DIR/vundle"
    git pull
    cd - > /dev/null
    echo "  ${GREEN}✓ 更新完成${RESET}"
else
    git clone https://gitee.com/hzx_3/vundle.git "$OFFLINE_DIR/vundle"
    echo "  ${GREEN}✓ 克隆完成${RESET}"
fi

echo ""
echo "================================================================"
echo "  ${GREEN}✓ 所有资源下载完成！${RESET}"
echo "================================================================"
echo ""
echo "离线资源目录: ${BLUE}${OFFLINE_DIR}${RESET}"
echo ""
echo "文件列表:"
ls -lh "$OFFLINE_DIR" | tail -n +2 | awk '{print "  - " $9 " (" $5 ")"}'
if [ -d "$OFFLINE_DIR/zsh-autosuggestions" ]; then
    echo "  - zsh-autosuggestions/ (Git仓库)"
fi
if [ -d "$OFFLINE_DIR/zsh-syntax-highlighting" ]; then
    echo "  - zsh-syntax-highlighting/ (Git仓库)"
fi
echo ""
echo "下一步："
echo "  1. 将整个 init-ubuntu 目录打包"
echo "  2. 传输到目标服务器"
echo "  3. 运行 init_env_offline.sh 进行安装"
echo ""
