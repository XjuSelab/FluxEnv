#!/bin/bash

# ==============================================
# Ubuntu 系统初始化脚本 - 离线版 + VPN
# 功能：用户创建、Starship安装、Zsh配置、Xray VPN
# ==============================================

set -e  # 遇到错误立即退出

# 脚本目录和离线资源目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OFFLINE_DIR="$SCRIPT_DIR/offline_resources"

# 阶段进度显示
TOTAL_STAGES=11  # 增加到11个阶段（新增VPN和Vim）
current_stage=0

show_stage() {
    current_stage=$((current_stage + 1))
    echo ""
    echo "================================================================"
    echo "  [阶段 ${current_stage}/${TOTAL_STAGES}] $1"
    echo "================================================================"
}

show_progress() {
    echo "  → $1"
}

# ==============================================
# 阶段 0: 颜色设置和初始化
# ==============================================
setup_color() {
    if [ -t 1 ]; then
        RED=$(printf '\033[31m')
        GREEN=$(printf '\033[32m')
        YELLOW=$(printf '\033[33m')
        BLUE=$(printf '\033[34m')
        BOLD=$(printf '\033[1m')
        RESET=$(printf '\033[m')
    else
        RED=""
        GREEN=""
        YELLOW=""
        BLUE=""
        BOLD=""
        RESET=""
    fi
}

setup_color

show_stage "系统初始化检查"

# Root权限检查
username_check=`whoami`
if [[ ! ${username_check} == "root" ]];then
    echo "${RED}错误：请使用root用户执行该脚本${RESET}"
    exit 1
fi
show_progress "Root权限检查通过 ✓"

# 检测CPU架构
show_progress "检测CPU架构..."
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)
        XRAY_ZIP="Xray-linux-64.zip"
        show_progress "检测到架构: x86_64"
        ;;
    aarch64|arm64)
        XRAY_ZIP="Xray-linux-arm64-v8a.zip"
        show_progress "检测到架构: ARM64"
        ;;
    *)
        echo "${YELLOW}警告: 未识别的架构 $ARCH，跳过Xray安装${RESET}"
        XRAY_ZIP=""
        ;;
esac

# ==============================================
# 阶段 1: 系统更新和软件包安装 (优化容错版)
# ==============================================
show_stage "系统更新和软件包安装"

# 1. 清理可能损坏的列表缓存 (这是解决你报错的关键)
show_progress "清理旧的软件源缓存..."
rm -rf /var/lib/apt/lists/*

# 2. 尝试更新源，允许失败 (关键修改：|| true)
# 说明：如果 apt update 报错，打印警告但不退出脚本，继续尝试后续步骤
show_progress "更新软件源信息..."
apt update || echo "${YELLOW}警告: 软件源更新遇到问题，将尝试使用现有缓存继续安装...${RESET}"

# 3. 尝试修复潜在的依赖破坏
show_progress "检查并修复依赖关系..."
apt install -f -y

# 4. 升级系统 (如果 update 失败，这一步可能不会做太多事，但不会报错)
show_progress "升级系统软件包..."
# DEBIAN_FRONTEND=noninteractive 防止升级过程中弹出弹窗卡住脚本
DEBIAN_FRONTEND=noninteractive apt upgrade -y || echo "${YELLOW}警告: 系统升级未完全完成，跳过...${RESET}"

show_progress "清理不需要的软件包..."
apt autoremove -y

show_progress "安装基础工具..."
# 同样允许安装过程中出现小错误
apt install -y wget curl unzip jq || echo "${YELLOW}警告: 部分基础工具安装失败${RESET}"

show_progress "安装开发依赖软件..."
apt install -y git zsh gcc g++ glibc-doc autojump universal-ctags || echo "${YELLOW}警告: 部分开发依赖安装失败${RESET}"

echo "${GREEN}✓ 软件包安装阶段结束${RESET}"

# ==============================================
# 阶段 2: SSH配置优化
# ==============================================
show_stage "SSH配置优化"

show_progress "备份SSH配置文件..."
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup.$(date +%Y%m%d_%H%M%S)

n=`grep -n "ClientAliveInterval " /etc/ssh/sshd_config | awk -F':' '{print $1}'`
TMPn='ClientAliveInterval 60'
m=`grep -n "ClientAliveCountMax " /etc/ssh/sshd_config | awk -F':' '{print $1}'`
TMPm='ClientAliveCountMax 3'

if [ -n "$n" ]; then
    show_progress "配置SSH保持连接超时时间..."
    sed -i "${n}c $TMPn" /etc/ssh/sshd_config
fi

if [ -n "$m" ]; then
    show_progress "配置SSH保持连接次数..."
    sed -i "${m}c $TMPm" /etc/ssh/sshd_config
fi

show_progress "重启SSH服务..."
systemctl restart sshd 2>/dev/null || service ssh restart

echo "${GREEN}✓ SSH配置完成${RESET}"

# ==============================================
# 阶段 3: 主机名设置
# ==============================================
show_stage "主机名配置"

regex="^[a-zA-Z][a-zA-Z0-9_-]*$"

while [[ 1 ]];do
    echo ""
    read -p "请设置一个${RED}主机名${RESET}(${YELLOW}字母开头，可含数字、下划线、连字符${RESET}) :" host_name
    if [[ ! ${host_name} =~ ${regex} ]];then
        echo "${RED}主机名不符合规则，请重新输入${RESET}"
        continue
    else
        break
    fi
done

show_progress "设置主机名为: ${host_name}"
hostnamectl set-hostname ${host_name}
echo "${GREEN}✓ 主机名设置完成${RESET}"

show_progress "获取本机IP地址..."
if command -v ip &> /dev/null; then
    host_ip=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v 127.0.0.1 | head -1)
else
    host_ip=`ifconfig eth0 2>/dev/null | grep inet | grep -v 127.0.0.1 | grep -v inet6 | awk '{print $2}' | tr -d "addr:" | head -1`
fi

if [ -z "$host_ip" ]; then
    echo "${YELLOW}警告: 无法获取IP地址，跳过/etc/hosts配置${RESET}"
else
    show_progress "本机IP: ${host_ip}"
    show_progress "备份/etc/hosts文件..."
    cp /etc/hosts /etc/hosts.backup.$(date +%Y%m%d_%H%M%S)

    show_progress "更新/etc/hosts配置..."
    host_line_num=`grep -n "$host_ip" /etc/hosts | head -1 | awk -F':' '{print $1}'`

    if [ -z "$host_line_num" ]; then
        show_progress "追加主机名映射到/etc/hosts"
        echo "$host_ip	${host_name}	${host_name}" >> /etc/hosts
    else
        show_progress "更新现有主机名映射"
        host_line_content="$host_ip	${host_name}	${host_name}"
        sed -i "${host_line_num}c $host_line_content" /etc/hosts
    fi

    echo "${GREEN}✓ /etc/hosts配置完成${RESET}"
fi

# ==============================================
# 阶段 4: 用户创建
# ==============================================
show_stage "用户创建"

while [[ 1 ]];do
    echo ""
    read -p "请输入你的${RED}用户名${RESET}（${YELLOW}字母开头，可含数字下划线${RESET}）:" username
    if [[ ! ${username} =~ ${regex} ]];then
        echo "${RED}用户名不符合规则，请重新输入${RESET}"
        continue
    else
        if id "$username" &>/dev/null; then
            echo "${YELLOW}警告: 用户 $username 已存在${RESET}"
            read -p "是否删除并重新创建? (y/n): " confirm
            if [[ ${confirm} != 'y' ]];then
                continue
            fi
        fi
        break
    fi
done

while [[ 1 ]];do
    echo ""
    read -p "请为用户${BLUE}${username}${RESET}设置一个${RED}密码${RESET} :" USER_PASSWD
    read -p "你的密码为${GREEN}${USER_PASSWD}${RESET},请输入${YELLOW}y${RESET}确认,其他任何字符将重新设置密码 [y/n]:" in_tmp
    if [[ ${in_tmp} == 'y' ]];then
        break
    else
        continue
    fi
done

show_progress "创建用户: ${username}"
if id "$username" &>/dev/null; then
    userdel -rf ${username}
    show_progress "已删除旧用户"
fi

useradd ${username} -G sudo -m && show_progress "用户创建成功 ✓" || {
    echo "${RED}用户创建失败${RESET}"
    exit 1
}

sleep 1

show_progress "设置用户密码..."
echo "${username}:${USER_PASSWD}" | chpasswd

if [ $? -eq 0 ]; then
    echo "${GREEN}✓ 密码设置成功${RESET}"
else
    echo "${RED}密码设置失败${RESET}"
    exit 1
fi

# ==============================================
# 阶段 5: Sudo权限配置
# ==============================================
show_stage "配置Sudo权限（临时无密码）"

show_progress "备份sudoers文件..."
cp /etc/sudoers /etc/sudoers.backup.$(date +%Y%m%d_%H%M%S)

show_progress "创建临时sudo权限配置..."
cat > /etc/sudoers.d/temp_install << 'EOF'
%sudo ALL=(ALL:ALL) NOPASSWD: ALL
Defaults   visiblepw
EOF
chmod 440 /etc/sudoers.d/temp_install

echo "${GREEN}✓ 临时sudo权限已启用${RESET}"

# ==============================================
# 阶段 6: 安装Xray VPN
# ==============================================
show_stage "安装Xray VPN"

if [ -n "$XRAY_ZIP" ] && [ -f "$SCRIPT_DIR/$XRAY_ZIP" ]; then
    show_progress "解压Xray..."
    unzip -o "$SCRIPT_DIR/$XRAY_ZIP" -d /usr/local/xray
    chmod +x /usr/local/xray/xray

    show_progress "安装Xray到系统路径..."
    install -m 0755 /usr/local/xray/xray /usr/local/bin/xray

    show_progress "安装geo数据文件..."
    mkdir -p /usr/local/share/xray
    cp -f /usr/local/xray/geo* /usr/local/share/xray/ 2>/dev/null || true

    show_progress "创建配置目录..."
    mkdir -p /usr/local/etc/xray

    show_progress "验证Xray安装..."
    if xray --version &>/dev/null; then
        XRAY_VERSION=$(xray --version | head -1)
        echo "  ${GREEN}✓ Xray安装成功: $XRAY_VERSION${RESET}"

        # 询问是否配置VPN
        echo ""
        read -p "是否现在配置VPN连接? (y/n): " config_vpn
        if [[ ${config_vpn} == 'y' ]]; then
            echo ""
            echo "${BLUE}请输入VPN配置信息：${RESET}"
            read -p "服务器域名 (例如: my-domain.online): " vpn_domain
            read -p "用户UUID (例如: bf182c5b-bb65-49fa-a84c-506263fa5f4d): " vpn_uuid

            show_progress "创建Xray配置文件..."
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
            "users": [
              {
                "id": "${vpn_uuid}",
                "encryption": "none",
                "flow": "xtls-rprx-vision"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "serverName": "${vpn_domain}"
        }
      }
    }
  ]
}
EOF
            echo "  ${GREEN}✓ VPN配置文件创建成功${RESET}"
        else
            echo "${YELLOW}跳过VPN配置，稍后可手动配置 /usr/local/etc/xray/config.json${RESET}"
        fi
    else
        echo "${YELLOW}警告: Xray安装验证失败${RESET}"
    fi

    # 复制VPN控制脚本到用户目录
    show_progress "安装VPN控制脚本..."
    mkdir -p /home/${username}/bin

    if [ -f "$SCRIPT_DIR/start-vpn.sh" ]; then
        cp "$SCRIPT_DIR/start-vpn.sh" /home/${username}/bin/start-vpn
        chmod +x /home/${username}/bin/start-vpn
        show_progress "已安装: ~/bin/start-vpn ✓"
    fi

    if [ -f "$SCRIPT_DIR/stop-vpn.sh" ]; then
        cp "$SCRIPT_DIR/stop-vpn.sh" /home/${username}/bin/stop-vpn
        chmod +x /home/${username}/bin/stop-vpn
        show_progress "已安装: ~/bin/stop-vpn ✓"
    fi

    chown -R ${username}:${username} /home/${username}/bin

else
    echo "${YELLOW}未找到Xray压缩包 ($XRAY_ZIP)，跳过VPN安装${RESET}"
fi

echo "${GREEN}✓ Xray VPN安装完成${RESET}"

# ==============================================
# 阶段 7: 安装Starship和Zsh插件（离线优先）
# ==============================================
show_stage "安装Starship和Zsh环境（使用离线资源）"

show_progress "安装Starship prompt..."
if [ -f "$OFFLINE_DIR/starship-x86_64-unknown-linux-gnu.tar.gz" ]; then
    show_progress "使用本地Starship二进制文件..."
    tar -xzf "$OFFLINE_DIR/starship-x86_64-unknown-linux-gnu.tar.gz" -C /tmp
    mv /tmp/starship /usr/local/bin/
    chmod +x /usr/local/bin/starship
    echo "  ${GREEN}✓ Starship安装成功（离线）${RESET}"
elif [ -f "$OFFLINE_DIR/starship_install.sh" ]; then
    show_progress "使用本地安装脚本..."
    bash "$OFFLINE_DIR/starship_install.sh" -y
    echo "  ${GREEN}✓ Starship安装成功（本地脚本）${RESET}"
else
    show_progress "使用在线安装..."
    curl -sS https://starship.rs/install.sh | sh -s -- -y
    echo "  ${GREEN}✓ Starship安装成功（在线）${RESET}"
fi

if ! command -v starship &> /dev/null; then
    echo "${YELLOW}警告: Starship安装可能失败，但继续执行...${RESET}"
fi

show_progress "创建zsh插件目录..."
mkdir -p /home/${username}/.zsh/plugins

show_progress "安装zsh-autosuggestions插件..."
if [ -d "$OFFLINE_DIR/zsh-autosuggestions" ]; then
    show_progress "使用本地资源..."
    cp -r "$OFFLINE_DIR/zsh-autosuggestions" /home/${username}/.zsh/plugins/
    echo "  ${GREEN}✓ zsh-autosuggestions安装成功（离线）${RESET}"
else
    show_progress "在线克隆..."
    git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions /home/${username}/.zsh/plugins/zsh-autosuggestions || {
        echo "${YELLOW}警告: zsh-autosuggestions克隆失败${RESET}"
    }
fi

show_progress "安装zsh-syntax-highlighting插件..."
if [ -d "$OFFLINE_DIR/zsh-syntax-highlighting" ]; then
    show_progress "使用本地资源..."
    cp -r "$OFFLINE_DIR/zsh-syntax-highlighting" /home/${username}/.zsh/plugins/
    echo "  ${GREEN}✓ zsh-syntax-highlighting安装成功（离线）${RESET}"
else
    show_progress "在线克隆..."
    git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting /home/${username}/.zsh/plugins/zsh-syntax-highlighting || {
        echo "${YELLOW}警告: zsh-syntax-highlighting克隆失败${RESET}"
    }
fi

echo "${GREEN}✓ Starship和插件安装完成${RESET}"

# ==============================================
# 阶段 8: 创建配置文件
# ==============================================
show_stage "创建Zsh和Starship配置文件"

show_progress "备份现有.zshrc（如果存在）..."
if [ -f /home/${username}/.zshrc ]; then
    mv /home/${username}/.zshrc /home/${username}/.zshrc.backup.$(date +%Y%m%d_%H%M%S)
fi

show_progress "创建.zshrc配置文件..."
cat > /home/${username}/.zshrc << 'ZSHRC_EOF'
# ==============================================
# 1. 初始化 Starship
# ==============================================
if command -v starship &> /dev/null; then
    eval "$(starship init zsh)"
fi

# ==============================================
# 2. 基础配置
# ==============================================
# 开启颜色
export CLICOLOR=1
export LSCOLORS=ExFxBxDxCxegedabagacad
alias ls='ls --color=auto'
alias ll='ls -lh --color=auto'
alias grep='grep --color=auto'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"

# 历史记录配置
HISTFILE="$HOME/.zsh_history"
HISTSIZE=10000
SAVEHIST=10000
setopt EXTENDED_HISTORY
setopt SHARE_HISTORY
setopt HIST_EXPIRE_DUPS_FIRST
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_FIND_NO_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_SAVE_NO_DUPS
setopt HIST_REDUCE_BLANKS

# 补全系统初始化
autoload -Uz compinit
compinit

# ==============================================
# 3. VPN 快捷命令
# ==============================================
# 添加 ~/bin 到 PATH
export PATH="$HOME/bin:$PATH"

# VPN 别名
alias start-vpn='source ~/bin/start-vpn'
alias stop-vpn='source ~/bin/stop-vpn'

# ==============================================
# end. 加载插件
# ==============================================
if [ -f ~/.zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]; then
    source ~/.zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
fi

if [ -f ~/.zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]; then
    source ~/.zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi
ZSHRC_EOF

if [ -f /home/${username}/.zshrc ]; then
    echo "${GREEN}✓ .zshrc创建成功${RESET}"
else
    echo "${RED}错误: .zshrc创建失败${RESET}"
    exit 1
fi

show_progress "创建starship配置目录..."
mkdir -p /home/${username}/.config

show_progress "创建starship.toml配置文件..."
cat > /home/${username}/.config/starship.toml << 'STARSHIP_EOF'
# ~/.config/starship.toml

[username]
style_user = "yellow bold"
style_root = "red bold"
format = "[$user]($style)"
show_always = true

[hostname]
ssh_only = false
format = "@[$hostname]($style) "
trim_at = "."
style = "blue"

[python]
disabled = true

[nodejs]
disabled = true

[golang]
disabled = true

[directory]
style = "yellow"
truncation_length = 4
truncation_symbol = "…/"
format = "[$path]($style)[$read_only]($read_only_style) "

[git_branch]
symbol = ""
style = "purple bold"
format = "[$symbol$branch]($style)"

[git_status]
disabled = false
format = ' ([$all_status$ahead_behind]($style) )'
style = "red bold"
staged = "[+](green) "
modified = "[!](red) "
untracked = "[?](yellow) "
deleted = "[✘](red) "
renamed = "[»](yellow) "
conflicted = "[=](red bold) "
stashed = "[$](cyan) "
ahead = "⇡"
behind = "⇣"
diverged = "⇕"
up_to_date = ""

[conda]
disabled = false
ignore_base = false
style = "#78E08F bold"
symbol = ""
format = "[\\($symbol$environment\\)]($style) "

[character]
success_symbol = "[❯](white bold)"
error_symbol = "[❯](red bold)"
vimcmd_symbol = "[❮](green bold)"
STARSHIP_EOF

if [ -f /home/${username}/.config/starship.toml ]; then
    echo "${GREEN}✓ starship.toml创建成功${RESET}"
else
    echo "${RED}错误: starship.toml创建失败${RESET}"
    exit 1
fi

show_progress "设置文件所有权..."
chown -R ${username}:${username} /home/${username}/.zsh 2>/dev/null || true
chown ${username}:${username} /home/${username}/.zshrc
chown -R ${username}:${username} /home/${username}/.config

show_progress "设置默认shell为zsh..."
ZSH_PATH=$(which zsh)
if [ -z "$ZSH_PATH" ]; then
    echo "${RED}错误: 未找到zsh${RESET}"
    exit 1
fi

chsh -s "$ZSH_PATH" ${username}
if [ $? -eq 0 ]; then
    echo "${GREEN}✓ 默认shell设置成功${RESET}"
else
    echo "${YELLOW}警告: 默认shell设置失败，用户需要手动执行: chsh -s /usr/bin/zsh${RESET}"
fi

# ==============================================
# 阶段 9: 配置Vim（可选）
# ==============================================
show_stage "配置Vim编辑器（可选）"

echo ""
read -p "是否配置Vim编辑器? (y/n): " config_vim

if [[ ${config_vim} == 'y' ]]; then
    show_progress "安装vim相关软件包..."
    apt install -y vim xclip astyle python3-setuptools 2>/dev/null || {
        echo "${YELLOW}警告: 部分vim软件包安装失败${RESET}"
    }

    show_progress "配置vim环境..."

    # 备份现有vim配置
    if [ -d /home/${username}/.vim ]; then
        mv /home/${username}/.vim /home/${username}/.vim_old.$(date +%Y%m%d_%H%M%S)
        show_progress "已备份旧vim配置"
    fi

    if [ -f /home/${username}/.vimrc ]; then
        mv /home/${username}/.vimrc /home/${username}/.vimrc_old.$(date +%Y%m%d_%H%M%S)
        show_progress "已备份旧.vimrc"
    fi

    # 使用离线vim配置（如果存在）
    if [ -d "$OFFLINE_DIR/vim" ]; then
        show_progress "使用本地vim配置..."
        cp -r "$OFFLINE_DIR/vim" /home/${username}/.vim
        echo "  ${GREEN}✓ vim配置复制成功（离线）${RESET}"
    else
        show_progress "在线克隆vim配置..."
        su - ${username} -c "git clone https://gitee.com/hzx_3/vim.git ~/.vim" || {
            echo "${YELLOW}警告: vim配置克隆失败${RESET}"
        }
    fi

    # 复制vimrc
    if [ -f /home/${username}/.vim/.vimrc ]; then
        cp /home/${username}/.vim/.vimrc /home/${username}/.vimrc
        show_progress ".vimrc配置完成"
    fi

    # 安装Vundle插件管理器
    show_progress "安装Vundle插件管理器..."
    if [ -d "$OFFLINE_DIR/vundle" ]; then
        show_progress "使用本地Vundle..."
        mkdir -p /home/${username}/.vim/bundle
        cp -r "$OFFLINE_DIR/vundle" /home/${username}/.vim/bundle/vundle
        echo "  ${GREEN}✓ Vundle安装成功（离线）${RESET}"
    else
        show_progress "在线克隆Vundle..."
        su - ${username} -c "git clone https://gitee.com/hzx_3/vundle.git ~/.vim/bundle/vundle" || {
            echo "${YELLOW}警告: Vundle克隆失败${RESET}"
        }
    fi

    # 设置vim文件所有权
    chown -R ${username}:${username} /home/${username}/.vim 2>/dev/null
    chown ${username}:${username} /home/${username}/.vimrc 2>/dev/null

    show_progress "安装vim插件（这可能需要几分钟）..."
    # 创建临时日志文件
    su - ${username} -c "cat > /tmp/vim_install_log.txt << 'EOF'
程序正在自动安装vim插件
command-t插件需要等待时间较长，请耐心等待
切勿强制退出，否则会导致错误
安装完毕将自动退出
EOF"

    # 静默安装插件
    su - ${username} -c "vim /tmp/vim_install_log.txt -c 'BundleInstall' -c 'q' -c 'q' >/dev/null 2>&1" || {
        echo "${YELLOW}警告: vim插件安装可能未完成${RESET}"
    }

    rm -f /tmp/vim_install_log.txt

    echo "${GREEN}✓ Vim配置完成${RESET}"
else
    echo "${YELLOW}跳过Vim配置${RESET}"
fi

# ==============================================
# 阶段 10: 清理和完成
# ==============================================
show_stage "清理和完成配置"

show_progress "恢复sudo权限配置..."
rm -f /etc/sudoers.d/temp_install
echo "${GREEN}✓ Sudo权限已恢复正常${RESET}"

show_progress "验证sudo配置..."
if grep -q 'NOPASSWD' /etc/sudoers /etc/sudoers.d/* 2>/dev/null; then
    echo "${YELLOW}警告: 检测到NOPASSWD配置仍然存在${RESET}"
fi

show_progress "保留安装脚本（标记为已完成）..."
cd
if [ -f "$SCRIPT_DIR/init_env_full.sh" ]; then
    cp "$SCRIPT_DIR/init_env_full.sh" "$SCRIPT_DIR/init_env_full.sh.completed.$(date +%Y%m%d_%H%M%S)"
fi

# ==============================================
# 阶段 11: 显示完成信息
# ==============================================
show_stage "安装完成总结"

echo ""
echo "================================================================"
echo "  🎉 系统初始化完成！"
echo "================================================================"
echo ""
echo "  ${BLUE}用户信息：${RESET}"
echo "    用户名: ${username}"
echo "    密码: ${USER_PASSWD}"
echo ""
echo "  ${BLUE}已安装组件：${RESET}"
echo "    ✓ Zsh shell"
echo "    ✓ Starship prompt"
echo "    ✓ zsh-autosuggestions"
echo "    ✓ zsh-syntax-highlighting"
if [ -n "$XRAY_ZIP" ] && command -v xray &>/dev/null; then
    echo "    ✓ Xray VPN ($(xray --version | head -1))"
fi
if [[ ${config_vim} == 'y' ]] && [ -f /home/${username}/.vimrc ]; then
    echo "    ✓ Vim (已配置Vundle和插件)"
fi
echo ""
echo "  ${BLUE}VPN 使用方法：${RESET}"
echo "    启动VPN: ${GREEN}vpn-start${RESET} 或 ${GREEN}source ~/bin/start-vpn${RESET}"
echo "    停止VPN: ${GREEN}vpn-stop${RESET} 或 ${GREEN}source ~/bin/stop-vpn${RESET}"
echo "    配置文件: /usr/local/etc/xray/config.json"
echo ""
echo "  ${YELLOW}提示：${RESET}"
echo "    1. 请使用新用户登录系统"
echo "    2. 为了正确显示Starship图标，建议安装Nerd Font"
echo "    3. 访问 https://www.nerdfonts.com/ 下载字体"
echo "    4. VPN控制脚本位于 ~/bin/ 目录"
echo ""
echo "================================================================"

show_progress "切换到新用户..."
su - ${username}
