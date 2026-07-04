#!/bin/bash

# add_claude_user.sh —— 让机器上多个 Linux 用户共用同一个 Claude Code 登录。
#
# 做法:目标用户敲 claude 时经 sudo 切到"登录持有者"(默认 winbeau)身份运行,
#       但把环境变量对齐回目标用户,登录态经 ~/.claude 目录软链共享。
# 详见 docs/CLAUDE_SHARED_LOGIN.md。
#
# 用法:
#   sudo bash scripts/add_claude_user.sh dev3            # 新增/幂等接入 dev3
#   sudo bash scripts/add_claude_user.sh dev3 cleanup    # 仅移除 dev3(公共基建保留)
#   sudo CLAUDE_LOGIN_USER=alice bash scripts/add_claude_user.sh dev3   # 指定登录持有者

set -euo pipefail

LOGIN_USER="${CLAUDE_LOGIN_USER:-winbeau}"
SHARE_GROUP="${CLAUDE_SHARE_GROUP:-claudeshare}"
REAL_CLAUDE="/home/${LOGIN_USER}/.local/bin/claude"
WRAPPER="/usr/local/bin/claude"
HELPER="/usr/local/bin/claude-bridge"
SUDOERS="/etc/sudoers.d/claude-share"

NEW_USER="${1:-}"
ACTION="${2:-install}"

log()  { printf '  %s\n' "$*"; }
stage() { printf '\n=== %s ===\n' "$*"; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ]          || die "请用 sudo/root 运行"
[ -n "$NEW_USER" ]            || die "用法: sudo bash $0 <用户名> [cleanup]"
[ "$NEW_USER" != "$LOGIN_USER" ] || die "不能对登录持有者 $LOGIN_USER 自己操作"

# ---------------- cleanup ----------------
if [ "$ACTION" = "cleanup" ]; then
    stage "移除 $NEW_USER"
    if [ -L "/home/$NEW_USER/.claude" ]; then
        rm -f "/home/$NEW_USER/.claude"
        log "删 .claude 软链"
    fi
    rm -f "/home/$NEW_USER/.claude.json"
    if id "$NEW_USER" &>/dev/null; then
        userdel -r "$NEW_USER" 2>/dev/null && log "删用户 $NEW_USER(含家目录)"
    fi
    log "公共基建(组/wrapper/helper/sudoers)保留"
    exit 0
fi

[ -e "$REAL_CLAUDE" ] || die "登录持有者 $LOGIN_USER 的 claude 未找到于 $REAL_CLAUDE(先让它装好并 /login)"

install_sudoers() {
    # 先 visudo 校验再落盘,校验失败绝不碰真文件
    local tmp; tmp="$(mktemp)"
    printf '%%%s ALL=(%s) NOPASSWD:SETENV: %s, %s, %s\n' \
        "$SHARE_GROUP" "$LOGIN_USER" "$HELPER" "$REAL_CLAUDE" "$WRAPPER" > "$tmp"
    if visudo -cf "$tmp"; then
        install -m 440 -o root -g root "$tmp" "$SUDOERS"
        rm -f "$tmp"
    else
        rm -f "$tmp"
        die "sudoers 校验失败,未改动"
    fi
}

printf '########## 公共基建(幂等) ##########\n'

stage "[1] acl 工具"
command -v setfacl >/dev/null || { apt-get update -qq && apt-get install -y -qq acl; }
command -v setfacl >/dev/null || die "acl 安装失败"

stage "[2] 共享组 $SHARE_GROUP + 登录持有者 $LOGIN_USER 入组"
getent group "$SHARE_GROUP" >/dev/null || groupadd "$SHARE_GROUP"
usermod -aG "$SHARE_GROUP" "$LOGIN_USER"

stage "[3] helper $HELPER(以 $LOGIN_USER 跑,但环境对齐回调用者)"
cat > "$HELPER" <<EOF
#!/bin/sh
# 由 sudo 以 $LOGIN_USER 身份调用;把 HOME/USER/.. 钉回真实调用者(\$SUDO_USER),
# 清掉 sudo 留下的 SUDO_*,使 claude 的运行环境与"原生调用者的 claude"一致。
RU="\${SUDO_USER:-$LOGIN_USER}"
if [ "\$RU" != "$LOGIN_USER" ] && [ -L "/home/\$RU/.claude" ]; then
    [ -n "\${BRIDGE_PATH:-}" ] && PATH="\$BRIDGE_PATH"
    HOME="/home/\$RU"; USER="\$RU"; LOGNAME="\$RU"; MAIL="/var/mail/\$RU"
    export PATH HOME USER LOGNAME MAIL
    # 消除因 HOME=调用者 引起的假"安装损坏"自检(claude 内部标志,不碰 git/ssh/hf)
    export DISABLE_INSTALLATION_CHECKS=1
else
    HOME="/home/$LOGIN_USER"; export HOME
fi
unset SUDO_USER SUDO_UID SUDO_GID SUDO_COMMAND SUDO_PS1 BRIDGE_PATH
[ "\${1:-}" = "__envdump__" ] && exec env
exec "$REAL_CLAUDE" "\$@"
EOF
chmod 755 "$HELPER"

stage "[4] wrapper $WRAPPER($LOGIN_USER 直跑;他人 sudo 切过去并带过原生环境)"
cat > "$WRAPPER" <<EOF
#!/bin/sh
if [ "\$(id -un)" = "$LOGIN_USER" ]; then exec "$REAL_CLAUDE" "\$@"; fi
exec sudo -u $LOGIN_USER --preserve-env "BRIDGE_PATH=\$PATH" "$HELPER" "\$@"
EOF
chmod 755 "$WRAPPER"

stage "[5] sudoers(组级 + SETENV + NOPASSWD;仅放行 claude)"
install_sudoers
log "规则: $(cat "$SUDOERS")"

printf '\n########## 用户 %s ##########\n' "$NEW_USER"

stage "[6] 建用户 + 入组"
id "$NEW_USER" &>/dev/null || useradd -m -s /bin/bash "$NEW_USER"
usermod -aG "$SHARE_GROUP" "$NEW_USER"
log "组: $(id -nG "$NEW_USER")"

stage "[7] 开放 /home/$NEW_USER 给 $SHARE_GROUP(claude 任意目录可读写)"
setfacl -R -m  "g:${SHARE_GROUP}:rwx" "/home/$NEW_USER"
setfacl -R -dm "g:${SHARE_GROUP}:rwx" "/home/$NEW_USER"

stage "[8] 保护 .ssh(避免组权限触发 ssh StrictModes 拒绝私钥)"
mkdir -p "/home/$NEW_USER/.ssh"
setfacl -Rb "/home/$NEW_USER/.ssh"
setfacl -db "/home/$NEW_USER/.ssh"
chmod 700 "/home/$NEW_USER/.ssh"
chown -R "$NEW_USER":"$NEW_USER" "/home/$NEW_USER/.ssh"

stage "[9] .claude 目录软链 → $LOGIN_USER 的(共享登录;目录软链抗原子 rename)"
dot_claude="/home/$NEW_USER/.claude"
if [ -L "$dot_claude" ]; then
    ln -sfn "/home/$LOGIN_USER/.claude" "$dot_claude"
elif [ -e "$dot_claude" ]; then
    mv "$dot_claude" "${dot_claude}.bak.$(date +%s)"
    ln -s "/home/$LOGIN_USER/.claude" "$dot_claude"
else
    ln -s "/home/$LOGIN_USER/.claude" "$dot_claude"
fi
chown -h "$NEW_USER":"$NEW_USER" "$dot_claude" 2>/dev/null || true

stage "[10] .claude.json 拷贝(HOME 根文件,原子写不能软链;不含 token)"
dot_json="/home/$NEW_USER/.claude.json"
if [ -e "$dot_json" ] && [ ! -L "$dot_json" ]; then
    log "已存在,保留 $NEW_USER 自己的"
elif [ -f "/home/$LOGIN_USER/.claude.json" ]; then
    rm -f "$dot_json"
    cp "/home/$LOGIN_USER/.claude.json" "$dot_json"
    chown "$NEW_USER":"$SHARE_GROUP" "$dot_json"
    chmod 660 "$dot_json"
    log "已拷贝"
else
    log "$LOGIN_USER 无 .claude.json,跳过(claude 首跑会自建)"
fi

stage "[11] 自测:环境对齐 + 真跑"
# DISABLE_INSTALLATION_CHECKS 是有意注入的 claude 内部标志,比对时排除
env_filter='^(SUDO_[A-Z]*|_|SHLVL|PWD|OLDPWD|BRIDGE_PATH|DISABLE_INSTALLATION_CHECKS)='
native_env="$(mktemp)"; bridge_env="$(mktemp)"
sudo -u "$NEW_USER" bash -c 'env' 2>/dev/null | grep -vE "$env_filter" | sort > "$native_env" || true
sudo -u "$NEW_USER" bash -c \
    "sudo -n -u $LOGIN_USER --preserve-env \"BRIDGE_PATH=\$PATH\" $HELPER __envdump__" \
    2>/dev/null | grep -vE "$env_filter" | sort > "$bridge_env" || true
if diff -q "$native_env" "$bridge_env" >/dev/null; then
    log "✅ 环境变量与原生 $NEW_USER 一致(仅多注入 DISABLE_INSTALLATION_CHECKS,已知/有意)"
else
    log "⚠ env 差异:"
    diff -u "$native_env" "$bridge_env" | grep -E '^[+-]' | grep -vE '^[+-]{3}' | sed 's/^/    /'
fi
rm -f "$native_env" "$bridge_env"
printf '  真跑(借 %s 登录): ' "$LOGIN_USER"
sudo -u "$NEW_USER" -H bash -c "cd /home/$NEW_USER && timeout 90 claude -p 'reply with exactly: ok'" 2>/dev/null \
    || echo "(超时/需手动确认信任目录,不影响 env 结论)"

stage "完成"
log "$NEW_USER 登录后,任意目录敲 claude 即用 $LOGIN_USER 的登录;\$HOME/\$USER 等环境为原生 $NEW_USER"
log "移除: sudo bash $0 $NEW_USER cleanup"
