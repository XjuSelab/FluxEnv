#!/bin/bash

step_preflight() {
    stage "系统初始化检查"

    if [ "$(whoami)" != "root" ]; then
        die "请使用 root 用户执行该脚本"
    fi
    progress "Root 权限检查通过"

    if ! command_exists apt; then
        die "当前实现仅支持 apt 系发行版"
    fi

    ARCH="$(uname -m)"
    progress "检测到架构: $ARCH"

    if has_systemd; then
        INIT_SYSTEM="systemd"
    else
        INIT_SYSTEM="non-systemd"
    fi

    if is_container; then
        CONTAINER_MODE=1
        progress "检测到容器环境"
    else
        CONTAINER_MODE=0
        progress "检测到宿主机环境"
    fi

    if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER:-}" != "root" ]; then
        LAUNCH_MODE="sudo-user"
        INVOKING_USER="$SUDO_USER"
        progress "检测到 sudo 用户上下文: $INVOKING_USER"
    else
        LAUNCH_MODE="root-session"
        INVOKING_USER="root"
        progress "检测到 root 会话上下文"
    fi

    if [ "$PROFILE_NAME" = "standard" ] && [ "$LAUNCH_MODE" = "sudo-user" ]; then
        CREATE_USER=0
        TARGET_USER="$INVOKING_USER"
        TARGET_HOME="$(get_user_home "$TARGET_USER")"
        ENABLE_TEMP_SUDO=0
        FINAL_ACTION="none"
        progress "standard profile 将复用当前 sudo 用户: $TARGET_USER"
    fi

    if [ "$PROFILE_NAME" = "autodl" ]; then
        CREATE_USER=0
        ENABLE_TEMP_SUDO=0

        if [ "$LAUNCH_MODE" = "sudo-user" ]; then
            TARGET_USER="$INVOKING_USER"
            TARGET_HOME="$(get_user_home "$TARGET_USER")"
            progress "autodl profile 将复用当前 sudo 用户: $TARGET_USER"
        else
            TARGET_USER="root"
            TARGET_HOME="/root"
            progress "autodl profile 将继续配置 root 用户"
        fi
    fi

    if [ "$CREATE_USER" -eq 0 ]; then
        TARGET_USER="${TARGET_USER:-root}"
        TARGET_HOME="${TARGET_HOME:-$(get_user_home "$TARGET_USER")}"
    fi
}
