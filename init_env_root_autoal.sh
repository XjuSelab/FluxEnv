#!/bin/bash

# ==============================================
# AutoDL 专用初始化脚本 (V6: Root 极简版)
# 功能：配置 Root 用户的 Zsh + Starship(伪装主机名) + VPN
# 特点：不创建新用户，直接修改 Root 环境
# ==============================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OFFLINE_DIR="$SCRIPT_DIR/offline_resources"

# 进度显示
TOTAL_STAGES=8
current_stage=0

show_stage() {
    current_stage=$((current_stage + 1))
    echo -e "\n\033[1;34m================================================================\033[0m"
    echo -e "\033[1;34m  [阶段 ${current_stage}/${TOTAL_STAGES}] $1\033[0m"
    echo -e "\033[1;34m================================================================\033[0m"
}

setup_color() {
    RED=$(printf '\033[31m')
    GREEN=$(printf '\033[32m')
    YELLOW=$(printf '\033[33m')
    RESET=$(printf '\033[m')
}
setup_color

# ==============================================
# 阶段 1: 基础检查与更新
# ==============================================
show_stage "系统环境准备"

if [[ $(whoami) != "root" ]];then
    echo "${RED}错误：必须是 Root 用户${RESET}"
    exit 1
fi

# 架构检测
ARCH=$(uname -m)
case "$ARCH" in
    x86_64) XRAY_ZIP="Xray-linux-64.zip" ;;
    aarch64|arm64) XRAY_ZIP="Xray-linux-arm64-v8a.zip" ;;
    *) XRAY_ZIP="" ;;
esac

# 清理缓存并更新 (允许失败)
rm -rf /var/lib/apt/lists/*
apt update || echo "${YELLOW}警告: 源更新有误，尝试继续...${RESET}"

echo "安装基础工具..."
DEBIAN_FRONTEND=noninteractive apt install -y --no-install-recommends \
    wget curl unzip jq git zsh gcc g++ autojump nano vim \
    ca-certificates locales || echo "${YELLOW}部分软件安装失败${RESET}"

locale-gen en_US.UTF-8 >/dev/null 2>&1
export LANG=en_US.UTF-8

# ==============================================
# 阶段 2: SSH 优化
# ==============================================
show_stage "SSH 配置优化"
sed -i 's/^#ClientAliveInterval.*/ClientAliveInterval 60/' /etc/ssh/sshd_config 2>/dev/null || true
sed -i 's/^#ClientAliveCountMax.*/ClientAliveCountMax 3/' /etc/ssh/sshd_config 2>/dev/null || true
echo "${GREEN}✓ SSH 配置优化完成 (无需重启服务)${RESET}"

# ==============================================
# 阶段 3: 主机名伪装设置
# ==============================================
show_stage "设置主机名 (视觉伪装)"

regex="^[a-zA-Z][a-zA-Z0-9_-]*$"
while [[ 1 ]];do
    echo ""
    read -p "请设置显示的主机名 ${YELLOW}(如 rtx4090)${RESET}: " host_name
    [[ ${host_name} =~ ${regex} ]] && break || echo "${RED}格式错误${RESET}"
done

echo "${YELLOW}提示: AutoDL 锁定内核主机名，脚本将直接修改 Shell 提示符以显示 ${GREEN}${host_name}${RESET}"

# ==============================================
# 阶段 4: 安装 Xray VPN
# ==============================================
show_stage "安装 Xray VPN"

if [ -n "$XRAY_ZIP" ] && ( [ -f "$SCRIPT_DIR/$XRAY_ZIP" ] || [ -f "$OFFLINE_DIR/$XRAY_ZIP" ] ); then
    ZIP_PATH="$SCRIPT_DIR/$XRAY_ZIP"
    [ -f "$OFFLINE_DIR/$XRAY_ZIP" ] && ZIP_PATH="$OFFLINE_DIR/$XRAY_ZIP"
    
    unzip -o "$ZIP_PATH" -d /usr/local/xray >/dev/null
    install -m 0755 /usr/local/xray/xray /usr/local/bin/xray
    
    mkdir -p /usr/local/share/xray /usr/local/etc/xray
    cp -f /usr/local/xray/geo* /usr/local/share/xray/ 2>/dev/null || true

    echo ""
    read -p "是否配置 VPN 连接? (y/n): " config_vpn
    if [[ ${config_vpn} == 'y' ]]; then
        read -p "服务器域名: " vpn_domain
        read -p "用户 UUID: " vpn_uuid
        
        cat > /usr/local/etc/xray/config.json << EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    { "port": 10809, "listen": "127.0.0.1", "protocol": "socks", "settings": { "auth": "noauth" } },
    { "port": 10810, "listen": "127.0.0.1", "protocol": "http",  "settings": { "timeout": 0 } }
  ],
  "outbounds": [
    {
      "protocol": "vless",
      "settings": {
        "vnext": [ { "address": "${vpn_domain}", "port": 443, "users": [ { "id": "${vpn_uuid}", "encryption": "none", "flow": "xtls-rprx-vision" } ] } ]
      },
      "streamSettings": { "network": "tcp", "security": "tls", "tlsSettings": { "serverName": "${vpn_domain}" } }
    }
  ]
}
EOF
    fi

    # Root 用户的脚本放在 /root/bin
    mkdir -p /root/bin
    
    cat > /root/bin/start-vpn << 'EOF'
#!/bin/bash
nohup xray run -c /usr/local/etc/xray/config.json > /tmp/xray.log 2>&1 &
echo "Xray VPN 已启动"
export http_proxy=http://127.0.0.1:10810
export https_proxy=http://127.0.0.1:10810
export all_proxy=socks5://127.0.0.1:10809
echo "代理已开启"
EOF
    
    cat > /root/bin/stop-vpn << 'EOF'
#!/bin/bash
pkill -f xray
unset http_proxy https_proxy all_proxy
echo "Xray VPN 已停止"
EOF

    chmod +x /root/bin/*
    echo "${GREEN}✓ VPN 安装完成 (脚本在 ~/bin)${RESET}"
else
    echo "${YELLOW}跳过 VPN (未找到资源包)${RESET}"
fi

# ==============================================
# 阶段 5: Starship & Zsh 安装
# ==============================================
show_stage "安装 Zsh 与 Starship"

# Starship
if [ -f "$OFFLINE_DIR/starship-x86_64-unknown-linux-gnu.tar.gz" ]; then
    tar -xzf "$OFFLINE_DIR/starship-x86_64-unknown-linux-gnu.tar.gz" -C /usr/local/bin/
else
    if ! command -v starship &> /dev/null; then
        curl -sS https://starship.rs/install.sh | sh -s -- -y >/dev/null
    fi
fi

# Plugins
mkdir -p /root/.zsh/plugins
if [ -d "$OFFLINE_DIR/zsh-autosuggestions" ]; then
    cp -r "$OFFLINE_DIR/zsh-autosuggestions" /root/.zsh/plugins/
else
    git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions /root/.zsh/plugins/zsh-autosuggestions 2>/dev/null || true
fi

if [ -d "$OFFLINE_DIR/zsh-syntax-highlighting" ]; then
    cp -r "$OFFLINE_DIR/zsh-syntax-highlighting" /root/.zsh/plugins/
else
    git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting /root/.zsh/plugins/zsh-syntax-highlighting 2>/dev/null || true
fi

# ==============================================
# 阶段 6: 配置文件生成 (Root 专用)
# ==============================================
show_stage "生成 Root 配置文件"

# 1. 生成 .zshrc
cat > /root/.zshrc << EOF
# AutoDL Root Zsh Config

# 主机名伪装变量
export HOSTNAME="${host_name}"

# 环境变量
export PATH="\$HOME/bin:/usr/local/bin:\$PATH"
export LC_ALL=en_US.UTF-8

# 别名
alias ll='ls -lh --color=auto'
alias start-vpn='source ~/bin/start-vpn'
alias stop-vpn='source ~/bin/stop-vpn'
alias vi='vim'

# Starship
eval "\$(starship init zsh)"

# 插件
[ -f ~/.zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ] && source ~/.zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
[ -f ~/.zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ] && source ~/.zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
EOF

# 2. 生成 starship.toml (Root 风格 + 主机名伪装)
mkdir -p /root/.config
cat > /root/.config/starship.toml << EOF
# Starship Configuration

[username]
style_user = "yellow bold"
style_root = "red bold"  # Root 用户显示红色
format = "[\$user](\$style)"
show_always = true

# 禁用默认 Hostname 模块
[hostname]
disabled = true

# 视觉欺骗：显示自定义主机名
[custom.my_hostname]
command = "echo ${host_name}"
when = "true"
format = "@[\$output](blue bold) "

[directory]
style = "cyan"
truncation_length = 3
truncation_symbol = "…/"

[git_branch]
symbol = " "
style = "purple"

[character]
success_symbol = "[➜](bold red)" # Root 用户用红色箭头
error_symbol = "[✗](bold red)"
EOF

# ==============================================
# 阶段 7: Vim 配置
# ==============================================
show_stage "配置 Vim"
cat > /root/.vimrc << 'EOF'
set number
set mouse=a
set tabstop=4
set expandtab
syntax on
set cursorline
EOF
echo "${GREEN}✓ Vim 配置完成${RESET}"

# ==============================================
# 阶段 8: 完成与切换
# ==============================================
show_stage "切换到 Zsh"

echo "================================================================"
echo "  🎉 Root 环境初始化完毕！"
echo "  伪装主机名: ${host_name}"
echo "================================================================"

# 更改 Root 默认 Shell
chsh -s /bin/zsh root

# 直接进入 Zsh，不再需要 su
echo "${GREEN}正在进入 Zsh...${RESET}"
exec zsh -l
