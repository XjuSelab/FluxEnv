#!/bin/bash

load_defaults() {
    FLUXENV_ROOT="$1"
    OFFLINE_DIR="$FLUXENV_ROOT/offline_resources"
    PROFILE_STEPS="preflight packages ssh hostname user sudo vpn shell_env vim finalize"

    PROFILE_NAME="standard"
    CREATE_USER=1
    TARGET_USER=""
    TARGET_HOME=""
    FORCE_RECREATE_USER=0
    ENABLE_TEMP_SUDO=1
    ENABLE_VPN="ask"
    ENABLE_VIM="ask"
    VIM_MODE="full"
    INSTALL_VIM_PLUGINS=1
    ALLOW_ONLINE_FETCH=0
    STARSHIP_PRESET="bare-metal"
    VISUAL_HOSTNAME_ONLY=0
    RESTART_SSH=1
    CHANGE_DEFAULT_SHELL=1
    FINAL_ACTION="su"
    APT_FIX_BROKEN=1
    APT_UPGRADE=1
    BASE_PACKAGES="wget curl unzip jq git zsh gcc g++ autojump ca-certificates sudo locales"
    EXTRA_PACKAGES=""
    HOST_NAME=""
    USER_NAME=""
    USER_PASSWORD=""
    VPN_DOMAIN=""
    VPN_UUID=""
    XDG_TARGET_USER=""

    XRAY_ARCHIVE=""
    INIT_SYSTEM="unknown"
    CONTAINER_MODE=0
    VPN_ENABLED=0
    VIM_ENABLED=0
    VPN_INSTALLED=0
    STARSHIP_INSTALLED=0
}

load_profile() {
    local profile_name="$1"
    local profile_path="$FLUXENV_ROOT/profiles/${profile_name}.env"

    [ -f "$profile_path" ] || die "Unknown profile: $profile_name"

    # shellcheck source=/dev/null
    source "$profile_path"
    PROFILE_NAME="$profile_name"
}

load_env_file() {
    local path="$1"
    [ -f "$path" ] || die "Config file not found: $path"

    set -a
    # shellcheck source=/dev/null
    source "$path"
    set +a
}

finalize_config() {
    if is_true "${CREATE_USER:-0}"; then
        CREATE_USER=1
    else
        CREATE_USER=0
    fi

    if is_true "${ENABLE_TEMP_SUDO:-0}"; then
        ENABLE_TEMP_SUDO=1
    else
        ENABLE_TEMP_SUDO=0
    fi

    if is_true "${VISUAL_HOSTNAME_ONLY:-0}"; then
        VISUAL_HOSTNAME_ONLY=1
    else
        VISUAL_HOSTNAME_ONLY=0
    fi

    if is_true "${RESTART_SSH:-0}"; then
        RESTART_SSH=1
    else
        RESTART_SSH=0
    fi

    if is_true "${CHANGE_DEFAULT_SHELL:-0}"; then
        CHANGE_DEFAULT_SHELL=1
    else
        CHANGE_DEFAULT_SHELL=0
    fi

    if is_true "${ALLOW_ONLINE_FETCH:-0}"; then
        ALLOW_ONLINE_FETCH=1
    else
        ALLOW_ONLINE_FETCH=0
    fi

    if is_true "${APT_FIX_BROKEN:-0}"; then
        APT_FIX_BROKEN=1
    else
        APT_FIX_BROKEN=0
    fi

    if is_true "${APT_UPGRADE:-0}"; then
        APT_UPGRADE=1
    else
        APT_UPGRADE=0
    fi

    if is_true "${INSTALL_VIM_PLUGINS:-0}"; then
        INSTALL_VIM_PLUGINS=1
    else
        INSTALL_VIM_PLUGINS=0
    fi
}

resolve_toggle() {
    local variable_name="$1"
    local prompt_text="$2"
    local default_answer="${3:-n}"
    local raw_value="${!variable_name:-ask}"

    case "$raw_value" in
        ask|"")
            if prompt_yes_no "$prompt_text" "$default_answer"; then
                printf -v "$variable_name" "1"
            else
                printf -v "$variable_name" "0"
            fi
            ;;
        *)
            if is_true "$raw_value"; then
                printf -v "$variable_name" "1"
            else
                printf -v "$variable_name" "0"
            fi
            ;;
    esac

    export "$variable_name"
}
