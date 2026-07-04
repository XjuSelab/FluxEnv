#!/bin/bash

# ssh_disable_password.sh —— 关闭 SSH 密码登录(只留公钥),用于公网可达的机器加固。
#
# 带防锁死检查:关之前确认执行你的账号有可用的 authorized_keys,否则拒绝(避免把自己锁在门外)。
# 只影响新连接;现有 SSH 连接不受重载影响。可随时撤销。
#
# 用法:
#   sudo bash scripts/ssh_disable_password.sh          # 关闭密码登录(先做防锁死检查)
#   sudo FORCE=1 bash scripts/ssh_disable_password.sh  # 跳过检查强制关闭(慎用)
#   sudo bash scripts/ssh_disable_password.sh undo     # 撤销,恢复密码登录

set -euo pipefail

DROPIN="/etc/ssh/sshd_config.d/20-disable-password.conf"

log() { printf '  %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "请用 sudo/root 运行"

reload_sshd() {
    systemctl reload ssh 2>/dev/null \
        || systemctl reload sshd 2>/dev/null \
        || service ssh reload 2>/dev/null \
        || { log "请手动重载 sshd"; return 0; }
}

# ---------- 撤销 ----------
if [ "${1:-}" = "undo" ]; then
    rm -f "$DROPIN"
    if sshd -t; then reload_sshd; log "已恢复密码登录"; else die "sshd 校验失败"; fi
    exit 0
fi

# ---------- 防锁死检查 ----------
ADMIN="${SUDO_USER:-root}"
has_key=0
[ -s "/home/$ADMIN/.ssh/authorized_keys" ] && has_key=1
[ -s "/etc/ssh/authorized_keys/$ADMIN" ] && has_key=1
[ "$ADMIN" = "root" ] && [ -s "/root/.ssh/authorized_keys" ] && has_key=1

if [ "$has_key" -ne 1 ] && [ "${FORCE:-0}" != "1" ]; then
    die "账号 '$ADMIN' 没有可用的 authorized_keys —— 关闭密码登录会把你锁在门外!
       先给它加公钥(scripts/add_ssh_key.sh $ADMIN <pubkey>),或确认另有可登账号后用 FORCE=1 强制。"
fi
log "防锁死检查:'$ADMIN' 有可用公钥 ✓(或 FORCE=1)"

# ---------- 关闭密码登录 ----------
cat > "$DROPIN" <<'EOF'
# 只允许公钥登录,关闭密码 / 键盘交互认证。撤销:删本文件后 reload sshd。
PasswordAuthentication no
KbdInteractiveAuthentication no
EOF
chmod 644 "$DROPIN"

if sshd -t; then
    reload_sshd
    log "✅ 已关闭 SSH 密码登录(只留公钥);现有连接不受影响"
    log "撤销: sudo bash $0 undo"
else
    rm -f "$DROPIN"
    die "sshd 配置校验失败,已回滚,未生效"
fi
