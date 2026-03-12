#!/bin/bash

APT_BACKUP_DIR="/var/backups/fluxenv/apt"

update_hosts_file() {
    local resolved_ip=""
    if command_exists ip; then
        resolved_ip="$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '^127\.' | head -1)"
    elif command_exists ifconfig; then
        resolved_ip="$(ifconfig 2>/dev/null | awk '/inet / && $2 != "127.0.0.1" {print $2; exit}')"
    fi

    if [ -z "$resolved_ip" ]; then
        warn "无法解析主机 IPv4，跳过 /etc/hosts 更新"
        return 0
    fi

    progress "更新 /etc/hosts 中的主机名映射"
    if [ "${DRY_RUN:-0}" -eq 1 ]; then
        echo "    [dry-run] ${resolved_ip} ${HOST_NAME}"
        return 0
    fi

    backup_path /etc/hosts

    if grep -q "^${resolved_ip}[[:space:]]" /etc/hosts; then
        sed -i "s|^${resolved_ip}[[:space:]].*|${resolved_ip} ${HOST_NAME} ${HOST_NAME}|" /etc/hosts
    else
        printf '%s %s %s\n' "$resolved_ip" "$HOST_NAME" "$HOST_NAME" >> /etc/hosts
    fi
}

apply_apt_mirror() {
    local mirror_files=()
    local file_path=""

    if [ "$ENABLE_APT_MIRROR" -ne 1 ]; then
        progress "跳过 apt 换源"
        return 0
    fi

    if [ -f /etc/apt/sources.list ]; then
        mirror_files+=("/etc/apt/sources.list")
    fi

    while IFS= read -r file_path; do
        mirror_files+=("$file_path")
    done < <(find /etc/apt/sources.list.d -maxdepth 1 \( -name '*.list' -o -name '*.sources' \) 2>/dev/null | sort)

    if [ "${#mirror_files[@]}" -eq 0 ]; then
        warn "未找到可修改的 apt 源文件，跳过换源"
        return 0
    fi

    progress "应用 apt 镜像源: ${APT_MIRROR_PRESET} (${APT_UBUNTU_MIRROR})"
    if [ "${DRY_RUN:-0}" -eq 1 ]; then
        printf '    [dry-run] %s\n' "${mirror_files[@]}"
        return 0
    fi

    find /etc/apt/sources.list.d -maxdepth 1 -type f \( -name '*.list.backup.*' -o -name '*.sources.backup.*' \) -delete 2>/dev/null || true

    for file_path in "${mirror_files[@]}"; do
        backup_path_to_dir "$file_path" "$APT_BACKUP_DIR"
        sed -i \
            -e "s|https\?://archive\.ubuntu\.com/ubuntu|${APT_UBUNTU_MIRROR}|g" \
            -e "s|https\?://security\.ubuntu\.com/ubuntu|${APT_UBUNTU_MIRROR}|g" \
            -e "s|https\?://ports\.ubuntu\.com/ubuntu-ports|${APT_UBUNTU_PORTS_MIRROR}|g" \
            "$file_path"
    done
}

step_packages() {
    stage "系统更新和软件包安装"

    apply_apt_mirror
    try_shell "清理 apt 列表缓存" "rm -rf /var/lib/apt/lists/*"
    try_cmd "更新软件源信息" apt update

    if [ "$APT_FIX_BROKEN" -eq 1 ]; then
        try_cmd "修复潜在依赖问题" apt install -f -y
    fi

    if [ "$APT_UPGRADE" -eq 1 ]; then
        try_shell "升级系统软件包" "DEBIAN_FRONTEND=noninteractive apt upgrade -y"
        try_cmd "清理不需要的软件包" apt autoremove -y
    fi

    try_shell "安装基础软件包" "DEBIAN_FRONTEND=noninteractive apt install -y --no-install-recommends $BASE_PACKAGES $EXTRA_PACKAGES"
    try_shell "生成 en_US.UTF-8 locale" "locale-gen en_US.UTF-8 >/dev/null 2>&1"
}

step_ssh() {
    stage "SSH 配置优化"

    if [ ! -f /etc/ssh/sshd_config ]; then
        warn "未找到 /etc/ssh/sshd_config，尝试安装 openssh-server"
        try_shell "安装 openssh-server" "DEBIAN_FRONTEND=noninteractive apt install -y openssh-server"
    fi

    if [ ! -f /etc/ssh/sshd_config ]; then
        warn "openssh-server 安装后仍未找到 sshd_config，跳过 SSH 配置"
        return 0
    fi

    backup_path /etc/ssh/sshd_config
    set_sshd_option "ClientAliveInterval" "60"
    set_sshd_option "ClientAliveCountMax" "3"
    restart_ssh_service
}

step_hostname() {
    stage "主机名配置"

    prompt_value HOST_NAME "请输入主机名（字母开头，可含数字、下划线、连字符）" '^[a-zA-Z][a-zA-Z0-9_-]*$'
    progress "设置主机名为: $HOST_NAME"

    set_hostname_safe "$HOST_NAME"

    if [ "$VISUAL_HOSTNAME_ONLY" -eq 0 ]; then
        update_hosts_file
    fi
}
