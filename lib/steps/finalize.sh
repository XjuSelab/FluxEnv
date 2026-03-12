#!/bin/bash

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

    case "$FINAL_ACTION" in
        su)
            if [ "${DRY_RUN:-0}" -eq 0 ] && [ "$TARGET_USER" != "root" ]; then
                progress "切换到新用户 $TARGET_USER"
                exec su - "$TARGET_USER"
            fi
            ;;
        zsh)
            if [ "${DRY_RUN:-0}" -eq 0 ] && command_exists zsh; then
                progress "进入 zsh 登录 shell"
                exec zsh -l
            fi
            ;;
        *)
            progress "安装完成，请重新登录或手动切换 shell"
            ;;
    esac
}
