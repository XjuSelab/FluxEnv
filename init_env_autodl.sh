#!/bin/bash

# ==============================================
# AutoDL 专用初始化脚本 (v3: 修复 /etc/hosts 锁定问题)
# 功能：强制视觉伪装主机名、Zsh、Starship、VPN
# ==============================================

set -e

# 脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOTAL_STAGES=11
current_stage=0

# --- 辅助函数 ---
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

ARCH=$(uname -m)
case "$ARCH" in
    x86_64) XRAY_ZIP="Xray-linux-64.zip" ;;
    aarch64|arm64) XRAY_ZIP="Xray-linux-arm64-v8a.zip" ;;
    *) XRAY_ZIP="" ;;
esac

# ==============================================
# 阶段 1: 系统更新 (高容错版)
# ==============================================
show_stage "系统更新与基础软件"

rm -rf /var/lib/apt/lists/*
echo "${YELLOW}正在更新软件源...${RESET}"
apt update || echo "${YELLOW}Apt update 警告 (可忽略)${RESET}"

DEBIAN_FRONTEND=noninteractive apt install -y --no-install-recommends \
    wget curl unzip jq git zsh gcc g++ autojump nano vim \
    ca-certificates sudo locales || echo "${YELLOW}部分非核心软件安装失败，尝试继续...${RESET}"

locale-gen en_US.UTF-8 >/dev/null 2>&1
export LANG=en_US.UTF-8
echo "${GREEN}✓ 软件包安装完成${RESET}"

# ==============================================
# 阶段 2: SSH配置
# ==============================================
show_stage "SSH 配置优化"
sed -i 's/^#ClientAliveInterval.*/ClientAliveInterval 60/' /etc/ssh/sshd_config
sed -i 's/^#ClientAliveCountMax.*/ClientAliveCountMax 3/' /etc/ssh/sshd_config
echo "${GREEN}✓ SSH 配置优化完成${RESET}"

# ==============================================
# 阶段 3: 主机名设置 (Docker 锁死绕过版)
# ==============================================
show_stage "主机名配置 (AutoDL 兼容模式)"

regex="^[a-zA-Z][a-zA-Z0-9_-]*$"
while [[ 1 ]];do
    echo ""
    read -p "请设置一个${RED}主机名${RESET}: " host_name
    [[ ${host_name} =~ ${regex} ]] && break || echo "${RED}格式错误${RESET}"
done

echo "正在应用主机名: ${host_name}"

# 1. 尝试修改内核主机名 (允许失败)
hostname "${host_name}" 2>/dev/null || echo "${YELLOW}提示: 容器锁定内核主机名，已启用配置文件级伪装${RESET}"

# 2. 修复 /etc/hosts (修复 Device busy 报错)
HOST_IP=$(hostname -I | awk '{print $1}')
if [ -n "$HOST_IP" ]; then
    echo "正在更新 /etc/hosts ..."
    # 方法：不直接操作 /etc/hosts，而是操作临时文件，最后用 cat 回写内容
    cp /etc/hosts /tmp/hosts.tmp
    # 在临时文件中删除旧 IP 记录
    sed -i "/$HOST_IP/d" /tmp/hosts.tmp
    # 追加新记录
    echo "$HOST_IP  ${host_name}" >> /tmp/hosts.tmp
    # 关键点：用 cat > 覆盖内容，而不是 mv (避免 Device busy 错误)
    cat /tmp/hosts.tmp > /etc/hosts
    rm -f /tmp/hosts.tmp
    echo "${GREEN}✓ /etc/hosts 更新成功 (绕过挂载锁)${RESET}"
else
    echo "${YELLOW}警告: 无法获取 IP，跳过 hosts 配置${RESET}"
fi

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
    echo "${YELLOW}用户已存在，更新配置...${RESET}"
else
    useradd -m -s /bin/zsh -G sudo "$username"
fi
echo "${username}:${USER_PASSWD}" | chpasswd

# ==============================================
# 阶段 5: Sudo 权限
# ==============================================
echo "$username ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/nopasswd
chmod 0440 /etc/sudoers.d/nopasswd

# ==============================================
# 阶段 6: Xray VPN (仅解压)
# ==============================================
show_stage "检查 Xray VPN 资源"
if [ -n "$XRAY_ZIP" ] && [ -f "$SCRIPT_DIR/$XRAY_ZIP" ]; then
    unzip -o "$SCRIPT_DIR/$XRAY_ZIP" -d /usr/local/xray >/dev/null
    install -m 0755 /usr/local/xray/xray /usr/local/bin/xray
    mkdir -p /usr/local/share/xray /usr/local/etc/xray
    cp -f /usr/local/xray/geo* /usr/local/share/xray/ 2>/dev/null || true
    
    # 写入控制脚本
    mkdir -p /home/${username}/bin
    
    echo '#!/bin/bash' > /home/${username}/bin/start-vpn
    echo 'nohup xray run -c /usr/local/etc/xray/config.json > /tmp/xray.log 2>&1 &' >> /home/${username}/bin/start-vpn
    echo 'export http_proxy=http://127.0.0.1:10810; export https_proxy=http://127.0.0.1:10810; export all_proxy=socks5://127.0.0.1:10809' >> /home/${username}/bin/start-vpn
    echo 'echo "VPN Started"' >> /home/${username}/bin/start-vpn
    
    echo '#!/bin/bash' > /home/${username}/bin/stop-vpn
    echo 'pkill -f xray; unset http_proxy https_proxy all_proxy; echo "VPN Stopped"' >> /home/${username}/bin/stop-vpn
    
    chmod +x /home/${username}/bin/*
    chown -R ${username}:${username} /home/${username}/bin
    echo "${GREEN}✓ Xray 脚本已安装${RESET}"
else
    echo "跳过 VPN 安装"
fi

# ==============================================
# 阶段 7 & 8: Zsh + Starship (强制伪装主机名)
# ==============================================
show_stage "配置 Zsh 与 Starship"

# 安装 Starship
if ! command -v starship &> /dev/null; then
    curl -sS https://starship.rs/install.sh | sh -s -- -y >/dev/null
fi

# 准备插件
ZSH_CUSTOM="/home/${username}/.zsh"
mkdir -p "$ZSH_CUSTOM/plugins"
git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions" 2>/dev/null || true
git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" 2>/dev/null || true

# 生成 .zshrc
cat > /home/${username}/.zshrc << EOF
# Path
export PATH="\$HOME/bin:/usr/local/bin:\$PATH"

# Starship Init
eval "\$(starship init zsh)"

# Aliases
alias ll='ls -lh --color=auto'
alias start-vpn='source ~/bin/start-vpn'
alias stop-vpn='source ~/bin/stop-vpn'

# Plugins
[ -f ~/.zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ] && source ~/.zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
[ -f ~/.zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ] && source ~/.zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
EOF

# 生成 Starship 配置 (硬编码主机名)
mkdir -p /home/${username}/.config
cat > /home/${username}/.config/starship.toml << EOF
# Starship Configuration

[username]
style_user = "yellow bold"
style_root = "red bold"
format = "[\$user](\$style)"
show_always = true

# 禁用默认 Hostname 模块
[hostname]
disabled = true

# 使用自定义模块显示 "${host_name}"
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

# 权限修复
chown -R ${username}:${username} /home/${username}/.zshrc /home/${username}/.zsh /home/${username}/.config

# ==============================================
# 阶段 10: 完成
# ==============================================
show_stage "安装完成"
echo "================================================================"
echo "  🎉 V3 修复版环境初始化完毕！"
echo "  主机名 (伪装): ${host_name}"
echo "================================================================"
echo "  请执行: ${GREEN}su - ${username}${RESET}"

# 自动切换
su - ${username}
