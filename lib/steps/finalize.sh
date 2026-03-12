#!/bin/bash

enter_final_zsh() {
    local current_user=""
    local zsh_path=""

    if [ "${DRY_RUN:-0}" -eq 1 ]; then
        progress "进入 zsh 登录 shell"
        echo "    [dry-run] exec zsh -l"
        return 0
    fi

    if ! command_exists zsh; then
        progress "安装完成，请重新登录或手动切换 shell"
        return 0
    fi

    if [ ! -t 0 ] || [ ! -t 1 ]; then
        progress "检测到非交互终端，跳过自动进入 zsh"
        return 0
    fi

    current_user="$(id -un)"
    zsh_path="$(command -v zsh)"

    if [ -n "${TARGET_USER:-}" ] && [ "$TARGET_USER" != "$current_user" ]; then
        progress "切换到 $TARGET_USER 并进入 zsh 登录 shell"
        exec su - "$TARGET_USER" -s "$zsh_path"
    fi

    progress "进入 zsh 登录 shell"
    exec "$zsh_path" -l
}

step_finalize() {
    stage "清理和完成"

    if [ "$ENABLE_TEMP_SUDO" -eq 1 ]; then
        remove_path /etc/sudoers.d/temp_install
    fi

    echo ""
    echo "================================================================"
    echo "  🎉 FluxEnv 初始化完成"
    echo "================================================================"
    echo "  Profile: $PROFILE_NAME"
    echo "  用户: ${TARGET_USER}"
    echo "  主机名: ${HOST_NAME}"
    echo "  Init: ${INIT_SYSTEM}"
    echo "  容器环境: ${CONTAINER_MODE}"
    if [ "$VIM_ENABLED" -eq 1 ]; then
        echo "  Vim: 已配置"
    else
        echo "  Vim: 未配置"
    fi
    echo "================================================================"
    enter_final_zsh
}
