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

    detect_arch
    if [ -n "$XRAY_ARCHIVE" ]; then
        progress "检测到架构: $ARCH"
    else
        warn "未识别的架构 $ARCH，将跳过 Xray 安装"
    fi

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

    if [ "$CREATE_USER" -eq 0 ]; then
        TARGET_USER="${TARGET_USER:-root}"
        TARGET_HOME="${TARGET_HOME:-$(get_user_home "$TARGET_USER")}"
    fi
}
