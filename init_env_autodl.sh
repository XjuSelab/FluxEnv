#!/bin/bash

# ==============================================
# AutoDL 专用初始化脚本 (适配 Docker/Zsh)
# 功能：用户创建、Starship、Zsh、Xray VPN、主机名伪装
# ==============================================

set -e

# 脚本目录和离线资源目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OFFLINE_DIR="$SCRIPT_DIR/offline_resources"
TOTAL_STAGES=11
current_stage=0

# --- 辅助函数 ---
show_stage() {
    current_stage=$((current_stage + 1))
    echo -e "\n\033[1;34m================================================================\033[0m"
    echo -e "\033[1;34m  [阶段 ${current_stage}/${TOTAL_STAGES}] $1\033[0m"
    echo -e "\033[1;34m================================================================\033[0m"
}

show_progress() {
    echo "  → $1"
}

setup_color() {
    RED=$(printf '\033[31m')
    GREEN=$(printf '\033[32m')
    YELLOW=$(printf '\033[33m')
    BLUE=$(printf '\033[34m')
    RESET=$(printf '\033[m')
}
setup_color

# ==============================================
# 阶段 0: 环境检查
# ==============================================
show_stage "AutoDL 环境初始化检查"

if [[ $(whoami) != "root" ]];then
    echo "${RED}错误：请使用 root 用户执行此脚本${RESET}"
    exit 1
fi

# 检测是否为 AutoDL/Docker 环境 (通过检查 PID 1)
if [[ $(ps --no-headers -o comm 1) != "systemd" ]]; then
    IS_CONTAINER=true
    echo "${YELLOW}检测到容器环境 (无 Systemd)，将启用兼容模式${RESET}"
else
    IS_CONTAINER=false
fi

# 架构检测
ARCH=$(uname -m)
case "$ARCH" in
    x86_64) XRAY_ZIP="Xray-linux-64.zip" ;;
    aarch64|arm64) XRAY_ZIP="Xray-linux-arm64-v8a.zip" ;;
    *) XRAY_ZIP="" ;;
esac

# ==============================================
# 阶段 1: 系统更新 (AutoDL 优化版)
# ==============================================
show_stage "系统更新与基础软件"

# AutoDL 的 apt 有时会锁，先清理
rm -rf /var/lib/apt/lists/*

echo "${YELLOW}注意：AutoDL 源通常速度很快，但也可能偶发失败，脚本将尝试忽略非致命错误${RESET}"

# 更新源，允许失败
apt update || echo "${YELLOW}Apt update 遇到警告，尝试继续...${RESET}"

# 安装基础工具 (增加 --no-install-recommends 减少体积)
DEBIAN_FRONTEND=noninteractive apt install -y --no-install-recommends \
    wget curl unzip jq git zsh gcc g++ autojump nano vim \
    ca-certificates sudo locales || echo "${YELLOW}部分软件安装遇到问题${RESET}"

# 确保 locale 正常，否则 zsh 可能会乱码
locale-gen en_US.UTF-8
export LANG=en_US.UTF-8

echo "${GREEN}✓ 软件包安装完成${RESET}"

# ==============================================
# 阶段 2: SSH配置 (跳过 Systemd)
# ==============================================
show_stage "SSH 配置优化"

# AutoDL 的 SSH 是通过宿主机映射的，直接改 sshd_config 效果有限，但改 KeepAlive 有助于不掉线
sed -i 's/^#ClientAliveInterval.*/ClientAliveInterval 60/' /etc/ssh/sshd_config
sed -i 's/^#ClientAliveCountMax.*/ClientAliveCountMax 3/' /etc/ssh/sshd_config

if [ "$IS_CONTAINER" = true ]; then
    # 尝试用 service 命令重启，或者直接忽略
    service ssh restart 2>/dev/null || echo "${YELLOW}容器环境跳过 SSH 服务重启 (无需操作)${RESET}"
else
    systemctl restart sshd
fi

echo "${GREEN}✓ SSH 配置优化完成${RESET}"

# ==============================================
# 阶段 3: 主机名设置 (Docker 兼容版)
# ==============================================
show_stage "主机名配置 (AutoDL 兼容模式)"

regex="^[a-zA-Z][a-zA-Z0-9_-]*$"
while [[ 1 ]];do
    echo ""
    read -p "请设置一个${RED}主机名${RESET}: " host_name
    if [[ ! ${host_name} =~ ${regex} ]];then
        echo "${RED}格式错误 (仅限字母/数字/下划线)${RESET}"
        continue
    else
        break
    fi
done

# --- 核心修改：不使用 hostnamectl ---
echo "设置主机名为: ${host_name}"

# 1. 立即修改当前内核主机名 (容器内有效，重启失效)
hostname "${host_name}"

# 2. 持久化：将 hostname 命令写入全局 profile，确保每次启动 shell 都会重新设置名字
# 这样 Starship 就能读取到正确的名字了
if ! grep -q "hostname ${host_name}" /etc/profile; then
    echo "hostname ${host_name} >/dev/null 2>&1" >> /etc/profile
fi

# 3. 修改 hosts 文件 (防止 sudo 慢)
HOST_IP=$(hostname -I | awk '{print $1}')
if [ -n "$HOST_IP" ]; then
    if ! grep -q "${host_name}" /etc/hosts; then
        echo "$HOST_IP  ${host_name}" >> /etc/hosts
    fi
fi

echo "${GREEN}✓ 主机名已设置为 ${host_name} (已配置自动应用)${RESET}"

# ==============================================
# 阶段 4: 用户创建
# ==============================================
show_stage "创建非 Root 用户"

while [[ 1 ]];do
    echo ""
    read -p "请输入${RED}用户名${RESET}: " username
    [[ ${username} =~ ${regex} ]] && break
done

read -p "请设置${RED}密码${RESET}: " USER_PASSWD

if id "$username" &>/dev/null; then
    echo "${YELLOW}用户已存在，更新密码...${RESET}"
else
    # -s /bin/zsh 直接指定 zsh
    useradd -m -s /bin/zsh -G sudo "$username"
fi

echo "${username}:${USER_PASSWD}" | chpasswd
echo "${GREEN}✓ 用户 ${username} 准备就绪${RESET}"

# ==============================================
# 阶段 5: Sudo 权限
# ==============================================
show_stage "Sudo 免密配置"
echo "$username ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/nopasswd
chmod 0440 /etc/sudoers.d/nopasswd
echo "${GREEN}✓ Sudo 配置完成${RESET}"

# ==============================================
# 阶段 6: Xray VPN (文件安装)
# ==============================================
show_stage "安装 Xray VPN (客户端模式)"

if [ -n "$XRAY_ZIP" ] && [ -f "$SCRIPT_DIR/$XRAY_ZIP" ]; then
    unzip -o "$SCRIPT_DIR/$XRAY_ZIP" -d /usr/local/xray >/dev/null
    install -m 0755 /usr/local/xray/xray /usr/local/bin/xray
    
    # 复制 geo 文件
    mkdir -p /usr/local/share/xray
    cp -f /usr/local/xray/geo* /usr/local/share/xray/ 2>/dev/null || true
    
    mkdir -p /usr/local/etc/xray
    
    # 询问配置
    echo ""
    read -p "是否配置 VPN 连接信息? (y/n): " config_vpn
    if [[ ${config_vpn} == 'y' ]]; then
        read -p "服务器域名: " vpn_domain
        read -p "用户 UUID: " vpn_uuid
        
        # 写入配置文件
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
        "vnext": [
          {
            "address": "${vpn_domain}",
            "port": 443,
            "users": [ { "id": "${vpn_uuid}", "encryption": "none", "flow": "xtls-rprx-vision" } ]
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": { "serverName": "${vpn_domain}" }
      }
    }
  ]
}
EOF
    fi

    # 安装控制脚本 (Docker 中不能用 systemd，用脚本控制最稳)
    mkdir -p /home/${username}/bin
    
    # Start 脚本
    cat > /home/${username}/bin/start-vpn << 'EOF'
#!/bin/bash
nohup xray run -c /usr/local/etc/xray/config.json > /tmp/xray.log 2>&1 &
echo "Xray VPN 已在后台启动 (Logs: /tmp/xray.log)"
export http_proxy=http://127.0.0.1:10810
export https_proxy=http://127.0.0.1:10810
export all_proxy=socks5://127.0.0.1:10809
echo "代理环境变量已设置"
EOF

    # Stop 脚本
    cat > /home/${username}/bin/stop-vpn << 'EOF'
#!/bin/bash
pkill -f xray
unset http_proxy https_proxy all_proxy
echo "Xray VPN 已停止，代理变量已清除"
EOF

    chmod +x /home/${username}/bin/*
    chown -R ${username}:${username} /home/${username}/bin
    echo "${GREEN}✓ Xray 安装完成 (命令: start-vpn / stop-vpn)${RESET}"
else
    echo "${YELLOW}未找到 Xray 压缩包，跳过${RESET}"
fi

# ==============================================
# 阶段 7 & 8: Starship + Zsh 配置
# ==============================================
show_stage "配置 Zsh 与 Starship (AutoDL 适配)"

# 1. 安装 Starship
if command -v starship &> /dev/null; then
    echo "Starship 已安装"
else
    curl -sS https://starship.rs/install.sh | sh -s -- -y >/dev/null
fi

# 2. 准备插件目录
ZSH_CUSTOM="/home/${username}/.zsh"
mkdir -p "$ZSH_CUSTOM/plugins"

# 3. 安装插件 (优先尝试 git，失败则跳过)
git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions" 2>/dev/null || echo "Zsh 插件下载失败，跳过"
git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" 2>/dev/null || true

# 4. 生成 .zshrc
cat > /home/${username}/.zshrc << EOF
# AutoDL Zsh Config

# 1. 再次确保主机名被设置 (针对 Docker 重启后)
hostname ${host_name} >/dev/null 2>&1

# 2. Path 设置
export PATH="\$HOME/bin:/usr/local/bin:\$PATH"

# 3. 基础别名
alias ll='ls -lh --color=auto'
alias grep='grep --color=auto'
alias start-vpn='source ~/bin/start-vpn'
alias stop-vpn='source ~/bin/stop-vpn'

# 4. 初始化 Starship
eval "\$(starship init zsh)"

# 5. 加载插件
[ -f ~/.zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ] && source ~/.zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
[ -f ~/.zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ] && source ~/.zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
EOF

# 5. 生成 starship.toml
mkdir -p /home/${username}/.config
cat > /home/${username}/.config/starship.toml << 'EOF'
# Starship Configuration

[username]
style_user = "yellow bold"
style_root = "red bold"
format = "[$user]($style)"
show_always = true

[hostname]
ssh_only = false
# 这里很重要：style 设置为蓝色，格式为 @主机名
format = "@[$hostname]($style) "
style = "blue bold"
# 在 Docker 中 hostname 命令修改后，Starship 就能读到了

[directory]
style = "cyan"
truncation_length = 3
truncation_symbol = "…/"

[git_branch]
symbol = " "
style = "purple"

[character]
success_symbol = "[➜](bold green)"
error_symbol = "[✗](bold red)"
EOF

# 权限修复
chown -R ${username}:${username} /home/${username}/.zshrc /home/${username}/.zsh /home/${username}/.config

echo "${GREEN}✓ Zsh 环境配置完成${RESET}"

# ==============================================
# 阶段 9: Vim (精简版)
# ==============================================
show_stage "Vim 基础配置"
read -p "是否配置 Vim? (y/n): " config_vim
if [[ ${config_vim} == 'y' ]]; then
    # 简单写一个好用的 vimrc，不依赖复杂插件，防止 AutoDL 网络下载失败
    cat > /home/${username}/.vimrc << 'EOF'
set number
set ruler
set mouse=a
set autoindent
set smartindent
set tabstop=4
set shiftwidth=4
set expandtab
syntax on
set cursorline
EOF
    chown ${username}:${username} /home/${username}/.vimrc
    echo "${GREEN}✓ Vim 基础配置完成${RESET}"
fi

# ==============================================
# 阶段 10: 完成
# ==============================================
show_stage "安装完成"

echo "================================================================"
echo "  🎉 AutoDL 环境初始化完毕！"
echo "  用户: ${username}"
echo "  Shell: Zsh + Starship"
echo "================================================================"
echo "  请执行以下命令切换用户并开始使用："
echo "  ${GREEN}su - ${username}${RESET}"
echo "================================================================"

# 自动切换
su - ${username}
