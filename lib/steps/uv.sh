#!/bin/bash

system_uv_runs() {
    local install_dir="${UV_INSTALL_DIR:-/usr/local/bin}"

    [ -x "$install_dir/uv" ] && "$install_dir/uv" --version >/dev/null 2>&1
}

install_uv_system() {
    local install_dir="${UV_INSTALL_DIR:-/usr/local/bin}"
    local offline_installer="$OFFLINE_DIR/uv-install.sh"
    local offline_installer_found=0
    local quoted_install_dir=""

    if system_uv_runs; then
        progress "uv 已安装: $("$install_dir/uv" --version 2>/dev/null)"
        return 0
    fi

    run_cmd "创建 uv 系统安装目录" mkdir -p "$install_dir"

    if [ -f "$offline_installer" ]; then
        offline_installer_found=1
        if try_cmd "执行离线 uv 安装脚本" env UV_INSTALL_DIR="$install_dir" INSTALLER_NO_MODIFY_PATH=1 sh "$offline_installer"; then
            return 0
        fi
    fi

    if [ "$ALLOW_ONLINE_FETCH" -eq 1 ]; then
        printf -v quoted_install_dir "%q" "$install_dir"
        try_shell "在线安装 uv 到 $install_dir" "curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=$quoted_install_dir INSTALLER_NO_MODIFY_PATH=1 sh"
        return 0
    fi

    if [ "$offline_installer_found" -eq 1 ]; then
        warn "uv 离线安装失败，且 ALLOW_ONLINE_FETCH=0，已跳过 uv 安装"
    else
        warn "缺少离线资源: uv-install.sh，且 ALLOW_ONLINE_FETCH=0，已跳过 uv 安装"
    fi
}

step_uv() {
    stage "uv 系统安装"

    install_uv_system
}
