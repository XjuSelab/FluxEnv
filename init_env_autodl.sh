#!/bin/bash

# ==============================================
# AutoDL 专用初始化脚本 (V5: 全功能整合版)
# 功能：Zsh + Starship(硬编码主机名) + Xray VPN + Vim
# 适配：AutoDL/Docker 严格权限环境 (Read-only hosts)
# ==============================================

set -e

# 脚本目录和离线资源目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OFFLINE_DIR="$SCRIPT_DIR/offline_resources"

# 阶段进度显示
TOTAL_STAGES=11
current_stage=0

show_stage() {
    current_stage=$((current_stage + 1))
    echo ""
    echo -e "\033[1;34m================================================================\033[0m"
    echo -e "\033[1;34m  [阶段 ${current_stage}/${TOTAL_STAGES}] $1\033[0m"
    echo -e "\033[1;34m================================================================\033[0m"
}

show_progress() {
    echo "  → $1"
}

# ==============================================
# 阶段 0: 颜色设置和初始化
# ==============================================
setup_color() {
    RED=$(printf '\033[31m')
    GREEN=$(printf '\033[32m')
    YELLOW=$(printf '\033[33m')
    BLUE=$(printf '\033[34m')
    RESET=$(printf '\033[m')
}
setup_color

show_stage "系统初始化检查"

if [[ $(whoami) != "root" ]];then
    echo "${RED}错误：请使用 root 用户执行此脚本${RESET}"
    exit 1
fi
show_progress "Root权限检查通过 ✓"

# 架构检测
ARCH=$(uname -m)
case "$ARCH" in
    x86_64) XRAY_ZIP="Xray-linux-64.zip" ;;
    aarch64|arm64) XRAY_ZIP="Xray-linux-arm64-v8a.zip" ;;
    *) XRAY_ZIP="" ;;
esac

# ==============================================
# 阶段 1: 系统更新 (AutoDL 容错版)
# ==============================================
show_stage "系统更新和软件包安装"

rm -rf /var/lib/apt/lists/*
show_progress "更新软件源 (允许失败)..."
apt update || echo "${YELLOW}警告: 源更新遇到问题，尝试使用现有缓存...${RESET}"

show_progress "安装基础工具..."
DEBIAN_FRONTEND=noninteractive apt install -y --no-install-recommends \
    wget curl unzip jq git zsh gcc g++ autojump nano vim \
    ca-certificates sudo locales || echo "${YELLOW}部分非核心软件安装失败，尝试继续...${RESET}"

locale-gen en_US.UTF-8 >/dev/null 2>&1
export LANG=en_US.UTF-8

echo "${GREEN}✓ 软件包安装完成${RESET}"

# ==============================================
# 阶段 2: SSH配置 (跳过服务重启)
# ==============================================
show_stage "SSH配置优化"
# AutoDL 只需要改配置，不需要重启服务，因为 SSH 是宿主机接管的
sed -i 's/^#ClientAliveInterval.*/ClientAliveInterval 60/' /etc/ssh/sshd_config 2>/dev/null || true
sed -i 's/^#ClientAliveCountMax.*/ClientAliveCountMax 3/' /etc/ssh/sshd_config 2>/dev/null || true
echo "${GREEN}✓ SSH 配置优化完成${RESET}"

# ==============================================
# 阶段 3: 主机名设置 (V4 纯视觉伪装核心)
# ==============================================
show_stage "主机名配置 (AutoDL 兼容模式)"

regex="^[a-zA-Z][a-zA-Z0-9_-]*$"
while [[ 1 ]];do
    echo ""
    read -p "请设置一个${RED}主机名${RESET}(${YELLOW}字母开头，可含数字、下划线${RESET}) :" host_name
    if [[ ! ${host_name} =~ ${regex} ]];then
        echo "${RED}主机名不符合规则${RESET}"
        continue
    else
        break
    fi
done

echo "${YELLOW}提示: 检测到容器环境，将跳过系统级修改，仅在 Zsh/Starship 中进行视觉伪装。${RESET}"
echo "设置显示名称为: ${GREEN}${host_name}${RESET}"

# ==============================================
# 阶段 4: 用户创建
# ==============================================
show_stage "用户创建"

while [[ 1 ]];do
    echo ""
    read -p "请输入${RED}用户名${RESET}: " username
    if [[ ! ${username} =~ ${regex} ]];then
        echo "${RED}用户名不符合规则${RESET}"
        continue
    else
        if id "$username" &>/dev/null; then
            echo "${YELLOW}警告: 用户 $username 已存在${RESET}"
            read -p "是否删除并重新创建? (y/n): " confirm
            [[ ${confirm} != 'y' ]] && continue
        fi
        break
    fi
done

read -p "请设置${RED}密码${RESET}: " USER_PASSWD

if id "$username" &>/dev/null; then
    userdel -rf ${username}
fi

useradd -m -s /bin/zsh -G sudo "$username"
echo "${username}:${USER_PASSWD}" | chpasswd
echo "${GREEN}✓ 用户 ${username} 创建成功${RESET}"

# ==============================================
# 阶段 5: Sudo权限
# ==============================================
show_stage "配置Sudo权限"
echo "$username ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/nopasswd
chmod 0440 /etc/sudoers.d/nopasswd
echo "${GREEN}✓ Sudo 配置完成${RESET}"

# ==============================================
# 阶段 6: 安装Xray VPN
# ==============================================
show_stage "安装Xray VPN"

if [ -n "$XRAY_ZIP" ] && ( [ -f "$SCRIPT_DIR/$XRAY_ZIP" ] || [ -f "$OFFLINE_DIR/$XRAY_ZIP" ] ); then
    # 兼容两种路径查找 zip
    ZIP_PATH="$SCRIPT_DIR/$XRAY_ZIP"
    [ -f "$OFFLINE_DIR/$XRAY_ZIP" ] && ZIP_PATH="$OFFLINE_DIR/$XRAY_ZIP"
    
    show_progress "解压安装 Xray..."
    unzip -o "$ZIP_PATH" -d /usr/local/xray >/dev/null
    install -m 0755 /usr/local/xray/xray /usr/local/bin/xray
    
    mkdir -p /usr/local/share/xray
    cp -f /usr/local/xray/geo* /usr/local/share/xray/ 2>/dev/null || true
    mkdir -p /usr/local/etc/xray

    # 询问配置
    echo ""
    read -p "是否配置VPN连接? (y/n): " config_vpn
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

    # 生成控制脚本 (修复版)
    mkdir -p /home/${username}/bin
    
    cat > /home/${username}/bin/start-vpn << 'EOF'
#!/bin/bash
nohup xray run -c /usr/local/etc/xray/config.json > /tmp/xray.log 2>&1 &
echo "Xray VPN 已在后台启动"
export http_proxy=http://127.0.0.1:10810
export https_proxy=http://127.0.0.1:10810
export all_proxy=socks5://127.0.0.1:10809
echo "代理环境变量已设置"
EOF
    
    cat > /home/${username}/bin/stop-vpn << 'EOF'
#!/bin/bash
pkill -f xray
unset http_proxy https_proxy all_proxy
echo "Xray VPN 已停止，变量已清除"
EOF

    chmod +x /home/${username}/bin/*
    chown -R ${username}:${username} /home/${username}/bin
    echo "${GREEN}✓ Xray 安装完成${RESET}"
else
    echo "${YELLOW}未找到Xray压缩包，跳过${RESET}"
fi

# ==============================================
# 阶段 7: 安装 Starship & Zsh (离线/在线混合)
# ==============================================
show_stage "安装 Zsh 环境"

# Starship 安装
if [ -f "$OFFLINE_DIR/starship-x86_64-unknown-linux-gnu.tar.gz" ]; then
    tar -xzf "$OFFLINE_DIR/starship-x86_64-unknown-linux-gnu.tar.gz" -C /usr/local/bin/
else
    if ! command -v starship &> /dev/null; then
        curl -sS https://starship.rs/install.sh | sh -s -- -y >/dev/null
    fi
fi

# 插件安装
ZSH_CUSTOM="/home/${username}/.zsh"
mkdir -p "$ZSH_CUSTOM/plugins"

if [ -d "$OFFLINE_DIR/zsh-autosuggestions" ]; then
    cp -r "$OFFLINE_DIR/zsh-autosuggestions" "$ZSH_CUSTOM/plugins/"
else
    git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions" 2>/dev/null || true
fi

if [ -d "$OFFLINE_DIR/zsh-syntax-highlighting" ]; then
    cp -r "$OFFLINE_DIR/zsh-syntax-highlighting" "$ZSH_CUSTOM/plugins/"
else
    git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" 2>/dev/null || true
fi

echo "${GREEN}✓ Zsh 环境准备就绪${RESET}"

# ==============================================
# 阶段 8: 配置文件生成 (核心修复点)
# ==============================================
show_stage "生成配置文件 (注入主机名)"

# 生成 .zshrc
cat > /home/${username}/.zshrc << EOF
# AutoDL Zsh Config

# 1. 视觉伪装：设置环境变量
export HOSTNAME="${host_name}"

# 2. Path & Aliases
export PATH="\$HOME/bin:/usr/local/bin:\$PATH"
alias ll='ls -lh --color=auto'
alias start-vpn='source ~/bin/start-vpn'
alias stop-vpn='source ~/bin/stop-vpn'

# 3. Starship
eval "\$(starship init zsh)"

# 4. Plugins
[ -f ~/.zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ] && source ~/.zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
[ -f ~/.zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ] && source ~/.zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
EOF

# 生成 starship.toml (硬编码主机名)
mkdir -p /home/${username}/.config
cat > /home/${username}/.config/starship.toml << EOF
# Starship Configuration

[username]
style_user = "yellow bold"
style_root = "red bold"
format = "[\$user](\$style)"
show_always = true

# 禁用默认 hostname，改用自定义模块显示 "${host_name}"
[hostname]
disabled = true

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
success_symbol = "[➜](bold green)"
error_symbol = "[✗](bold red)"
EOF

chown -R ${username}:${username} /home/${username}/.zshrc /home/${username}/.zsh /home/${username}/.config

# ==============================================
# 阶段 9: Vim 配置 (保留原脚本逻辑)
# ==============================================
show_stage "配置 Vim (可选)"
echo ""
read -p "是否配置Vim? (y/n): " config_vim

if [[ ${config_vim} == 'y' ]]; then
    # 简易版配置，防止网络卡死
    cat > /home/${username}/.vimrc << 'EOF'
set number
set mouse=a
set smartindent
set tabstop=4
set expandtab
syntax on
EOF
    chown ${username}:${username} /home/${username}/.vimrc
    
    # 如果有离线资源则使用，否则跳过复杂插件安装
    if [ -d "$OFFLINE_DIR/vim" ]; then
        cp -r "$OFFLINE_DIR/vim" /home/${username}/.vim
        chown -R ${username}:${username} /home/${username}/.vim
    fi
    echo "${GREEN}✓ Vim 基础配置完成${RESET}"
fi

# ==============================================
# 阶段 10 & 11: 完成
# ==============================================
show_stage "安装完成"
echo "================================================================"
echo "  🎉 AutoDL 环境初始化完毕 (V5 整合版)！"
echo "  主机名 (伪装): ${host_name}"
echo "  用户: ${username}"
echo "================================================================"
echo "  请执行: ${GREEN}su - ${username}${RESET}"

# 自动切换
su - ${username}
