#!/bin/bash

get_wsl_default_user() {
    local file_path="${1:-/etc/wsl.conf}"

    [ -f "$file_path" ] || return 0

    awk '
        /^\[user\][[:space:]]*$/ { in_user=1; next }
        /^\[[^]]+\][[:space:]]*$/ { in_user=0 }
        in_user && /^[[:space:]]*default[[:space:]]*=/ {
            sub(/^[[:space:]]*default[[:space:]]*=[[:space:]]*/, "", $0)
            sub(/[[:space:]]*$/, "", $0)
            print
            exit
        }
    ' "$file_path"
}

write_wsl_default_user() {
    local target_user="$1"
    local file_path="/etc/wsl.conf"
    local temp_file=""

    if [ "${DRY_RUN:-0}" -eq 1 ]; then
        progress "更新 WSL 默认登录用户为: $target_user"
        echo "    [dry-run] write $file_path"
        return 0
    fi

    if [ -f "$file_path" ]; then
        backup_path "$file_path"
    fi

    temp_file="$(mktemp)"
    if [ -f "$file_path" ]; then
        awk -v target_user="$target_user" '
            BEGIN {
                in_user=0
                user_section_seen=0
                default_written=0
            }

            /^\[user\][[:space:]]*$/ {
                if (in_user && !default_written) {
                    print "default=" target_user
                }
                print
                in_user=1
                user_section_seen=1
                default_written=0
                next
            }

            /^\[[^]]+\][[:space:]]*$/ {
                if (in_user && !default_written) {
                    print "default=" target_user
                }
                in_user=0
                print
                next
            }

            {
                if (in_user && /^[[:space:]]*default[[:space:]]*=/) {
                    if (!default_written) {
                        print "default=" target_user
                        default_written=1
                    }
                    next
                }

                print
            }

            END {
                if (in_user && !default_written) {
                    print "default=" target_user
                }

                if (!user_section_seen) {
                    if (NR > 0) {
                        print ""
                    }
                    print "[user]"
                    print "default=" target_user
                }
            }
        ' "$file_path" > "$temp_file"
    else
        cat > "$temp_file" <<EOF
[user]
default=$target_user
EOF
    fi

    mv "$temp_file" "$file_path"
}

step_wsl_user() {
    stage "WSL 默认用户检查"

    if [ "${WSL_MODE:-0}" -ne 1 ]; then
        progress "当前不是 WSL 环境，跳过默认用户检查"
        return 0
    fi

    if [ "$PROFILE_NAME" != "standard" ]; then
        progress "当前 profile 不修改 WSL 默认用户"
        return 0
    fi

    if [ -z "${TARGET_USER:-}" ] || [ "$TARGET_USER" = "root" ]; then
        progress "当前目标用户不是普通用户，跳过 WSL 默认用户修改"
        return 0
    fi

    WSL_DEFAULT_USER="$(get_wsl_default_user)"
    if [ "$WSL_DEFAULT_USER" = "$TARGET_USER" ]; then
        progress "WSL 默认登录用户已匹配: $TARGET_USER"
        return 0
    fi

    write_wsl_default_user "$TARGET_USER"
    WSL_DEFAULT_USER="$TARGET_USER"
    WSL_DEFAULT_USER_CHANGED=1
    progress "已将 WSL 默认登录用户更新为: $TARGET_USER"
}
