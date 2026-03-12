#!/bin/bash

init_colors() {
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

word_count() {
    local words="$1"
    set -- $words
    echo "$#"
}

stage() {
    CURRENT_STAGE=$((CURRENT_STAGE + 1))
    echo ""
    echo "================================================================"
    echo "  [阶段 ${CURRENT_STAGE}/${TOTAL_STAGES}] $1"
    echo "================================================================"
}

progress() {
    echo "  → $1"
}

warn() {
    echo "${YELLOW}警告: $1${RESET}" >&2
}

die() {
    echo "${RED}错误: $1${RESET}" >&2
    exit 1
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

is_true() {
    case "${1:-}" in
        1|true|TRUE|yes|YES|y|Y|on|ON) return 0 ;;
        *) return 1 ;;
    esac
}

run_cmd() {
    local description="$1"
    shift
    progress "$description"
    if [ "${DRY_RUN:-0}" -eq 1 ]; then
        echo "    [dry-run] $*"
        return 0
    fi
    "$@"
}

run_shell() {
    local description="$1"
    local script="$2"
    progress "$description"
    if [ "${DRY_RUN:-0}" -eq 1 ]; then
        echo "    [dry-run] $script"
        return 0
    fi
    /bin/bash -lc "$script"
}

try_cmd() {
    local description="$1"
    shift
    if ! run_cmd "$description" "$@"; then
        warn "$description 失败，继续执行"
        return 1
    fi
    return 0
}

try_shell() {
    local description="$1"
    local script="$2"
    if ! run_shell "$description" "$script"; then
        warn "$description 失败，继续执行"
        return 1
    fi
    return 0
}

write_file() {
    local path="$1"
    local mode="${2:-}"
    local owner="${3:-}"

    if [ "${DRY_RUN:-0}" -eq 1 ]; then
        progress "写入文件: $path"
        cat >/dev/null
        return 0
    fi

    cat > "$path"

    if [ -n "$mode" ]; then
        chmod "$mode" "$path"
    fi

    if [ -n "$owner" ]; then
        chown "$owner" "$path"
    fi
}

backup_path() {
    local path="$1"
    if [ ! -e "$path" ]; then
        return 0
    fi

    if [ "${DRY_RUN:-0}" -eq 1 ]; then
        progress "备份路径: $path"
        return 0
    fi

    cp -a "$path" "${path}.backup.$(date +%Y%m%d_%H%M%S)"
}

remove_path() {
    local path="$1"
    if [ "${DRY_RUN:-0}" -eq 1 ]; then
        progress "删除路径: $path"
        return 0
    fi
    rm -rf "$path"
}

copy_path() {
    local src="$1"
    local dest="$2"
    if [ "${DRY_RUN:-0}" -eq 1 ]; then
        progress "复制: $src -> $dest"
        return 0
    fi
    cp -a "$src" "$dest"
}

get_user_home() {
    local user_name="$1"
    if [ "$user_name" = "root" ]; then
        echo "/root"
        return 0
    fi

    local resolved
    resolved="$(getent passwd "$user_name" | cut -d: -f6)"
    if [ -n "$resolved" ]; then
        echo "$resolved"
    else
        echo "/home/$user_name"
    fi
}

prompt_yes_no() {
    local prompt_text="$1"
    local default_value="${2:-n}"
    local answer=""

    if [ "${INTERACTIVE:-1}" -ne 1 ]; then
        [ "$default_value" = "y" ]
        return
    fi

    while true; do
        if [ "$default_value" = "y" ]; then
            read -r -p "$prompt_text [Y/n]: " answer
            answer="${answer:-y}"
        else
            read -r -p "$prompt_text [y/N]: " answer
            answer="${answer:-n}"
        fi

        case "$answer" in
            y|Y|yes|YES) return 0 ;;
            n|N|no|NO) return 1 ;;
            *) warn "请输入 y 或 n" ;;
        esac
    done
}

prompt_value() {
    local variable_name="$1"
    local prompt_text="$2"
    local regex="${3:-.*}"
    local current_value="${!variable_name:-}"
    local input_value=""

    if [ -n "$current_value" ]; then
        return 0
    fi

    if [ "${INTERACTIVE:-1}" -ne 1 ]; then
        die "缺少必需配置: $variable_name"
    fi

    while true; do
        read -r -p "$prompt_text: " input_value
        if [[ "$input_value" =~ $regex ]]; then
            printf -v "$variable_name" "%s" "$input_value"
            export "$variable_name"
            return 0
        fi
        warn "输入格式不合法，请重试"
    done
}

prompt_password() {
    local variable_name="$1"
    local prompt_text="$2"
    local password_one=""
    local password_two=""

    if [ -n "${!variable_name:-}" ]; then
        return 0
    fi

    if [ "${INTERACTIVE:-1}" -ne 1 ]; then
        die "缺少必需配置: $variable_name"
    fi

    while true; do
        read -r -s -p "$prompt_text: " password_one
        echo
        read -r -s -p "确认密码: " password_two
        echo

        if [ -z "$password_one" ]; then
            warn "密码不能为空"
            continue
        fi

        if [ "$password_one" != "$password_two" ]; then
            warn "两次输入的密码不一致"
            continue
        fi

        printf -v "$variable_name" "%s" "$password_one"
        export "$variable_name"
        return 0
    done
}

has_systemd() {
    [ -d /run/systemd/system ] && [ "$(ps -p 1 -o comm= 2>/dev/null)" = "systemd" ]
}

is_container() {
    grep -qaE 'docker|lxc|containerd|kubepods' /proc/1/cgroup 2>/dev/null || \
    [ -f /.dockerenv ] || \
    [ -f /run/.containerenv ]
}

set_sshd_option() {
    local key="$1"
    local value="$2"
    local file_path="${3:-/etc/ssh/sshd_config}"

    if [ "${DRY_RUN:-0}" -eq 1 ]; then
        progress "更新 SSH 配置: $key $value"
        return 0
    fi

    if grep -qE "^[#[:space:]]*${key}[[:space:]]+" "$file_path"; then
        sed -i "s|^[#[:space:]]*${key}[[:space:]].*|${key} ${value}|" "$file_path"
    else
        printf '\n%s %s\n' "$key" "$value" >> "$file_path"
    fi
}

restart_ssh_service() {
    if [ "${RESTART_SSH:-0}" -ne 1 ]; then
        progress "跳过 SSH 服务重启"
        return 0
    fi

    if has_systemd; then
        try_cmd "重启 SSH 服务" systemctl restart sshd || try_cmd "重启 SSH 服务" systemctl restart ssh
        return 0
    fi

    if command_exists service; then
        try_cmd "重启 SSH 服务" service ssh restart || try_cmd "重启 SSH 服务" service sshd restart
        return 0
    fi

    warn "未检测到可用的 SSH 服务管理器，已跳过重启"
}

set_hostname_safe() {
    local new_hostname="$1"

    if [ "${VISUAL_HOSTNAME_ONLY:-0}" -eq 1 ]; then
        progress "容器/AutoDL 模式下仅使用提示符主机名，不修改系统主机名"
        return 0
    fi

    if command_exists hostnamectl && has_systemd; then
        run_cmd "设置系统主机名" hostnamectl set-hostname "$new_hostname"
    else
        progress "写入 /etc/hostname"
        if [ "${DRY_RUN:-0}" -eq 0 ]; then
            printf '%s\n' "$new_hostname" > /etc/hostname
            if command_exists hostname; then
                hostname "$new_hostname" || true
            fi
        fi
    fi
}
