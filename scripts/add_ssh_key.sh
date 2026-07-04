#!/bin/bash

# add_ssh_key.sh —— 给指定用户加 SSH 公钥登录,打印客户端 ssh config,并【默认关闭密码登录】。
#
# 背景:add_claude_user.sh 用 ACL 把 claude-share 用户的家目录开成“组可写”(claude 桥接需要),
#       而 sshd StrictModes 默认会因家目录组可写而拒绝 ~/.ssh 里的公钥。
# 办法:把公钥放到 root 拥有的 /etc/ssh/authorized_keys/<user>(StrictModes 会通过),
#       并给 sshd 追加一个 AuthorizedKeysFile 位置(不动 ~/.ssh,不影响其它用户)。
#
# 用法:
#   sudo bash scripts/add_ssh_key.sh grapes "ssh-ed25519 AAAA... you@host"   # 直接给公钥串
#   sudo bash scripts/add_ssh_key.sh grapes ~/id_ed25519.pub                 # 给公钥文件
#   sudo bash scripts/add_ssh_key.sh grapes                                  # 从 stdin 粘贴
#   sudo KEEP_PASSWORD=1 bash scripts/add_ssh_key.sh grapes "..."            # 加完公钥【不】自动关密码登录

set -euo pipefail

USER_NAME="${1:-}"
KEY_ARG="${2:-}"
KEYDIR="/etc/ssh/authorized_keys"
SSHD_DROPIN="/etc/ssh/sshd_config.d/10-claude-share-keys.conf"
KEEP_PASSWORD="${KEEP_PASSWORD:-0}"   # =1 则加完公钥后【不】自动关闭密码登录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log()   { printf '  %s\n' "$*"; }
stage() { printf '\n=== %s ===\n' "$*"; }
die()   { printf 'error: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "请用 sudo/root 运行"
[ -n "$USER_NAME" ]  || die "用法: sudo bash $0 <用户名> [公钥串|公钥文件]  (省略则从 stdin 读)"
id "$USER_NAME" &>/dev/null || die "用户 $USER_NAME 不存在"

# ---------- 取公钥 ----------
if [ -z "$KEY_ARG" ]; then
    log "从 stdin 读取公钥(粘贴后按 Ctrl-D)..."
    PUBKEY="$(cat)"
elif [ -f "$KEY_ARG" ]; then
    PUBKEY="$(cat "$KEY_ARG")"
else
    PUBKEY="$KEY_ARG"
fi
PUBKEY="$(printf '%s' "$PUBKEY" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
printf '%s' "$PUBKEY" | grep -qE '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-|sk-ssh-ed25519@|sk-ecdsa-sha2-)' \
    || die "这不像 SSH 公钥(应以 ssh-ed25519/ssh-rsa/ecdsa-/sk- 开头): ${PUBKEY:0:40}..."

stage "[1] 写公钥到 $KEYDIR/$USER_NAME(root 拥有,绕开家目录组可写导致的 StrictModes 拒绝)"
install -d -m 755 -o root -g root "$KEYDIR"
touch "$KEYDIR/$USER_NAME"
if grep -qxF "$PUBKEY" "$KEYDIR/$USER_NAME" 2>/dev/null; then
    log "公钥已存在,跳过"
else
    printf '%s\n' "$PUBKEY" >> "$KEYDIR/$USER_NAME"
    log "已追加"
fi
chown root:root "$KEYDIR/$USER_NAME"
chmod 644 "$KEYDIR/$USER_NAME"

stage "[2] sshd 追加 key 位置(幂等,不动 ~/.ssh,不影响其它用户)"
if [ -f "$SSHD_DROPIN" ] && grep -q 'authorized_keys/%u' "$SSHD_DROPIN"; then
    log "drop-in 已存在: $SSHD_DROPIN"
else
    cat > "$SSHD_DROPIN" <<'EOF'
# 追加从 root 拥有的 /etc/ssh/authorized_keys/<user> 读取公钥的位置。
# 用于家目录被 ACL 开成组可写(claude 桥接)、StrictModes 会拒 ~/.ssh 的用户。
AuthorizedKeysFile .ssh/authorized_keys /etc/ssh/authorized_keys/%u
EOF
    chmod 644 "$SSHD_DROPIN"
    log "已写 $SSHD_DROPIN"
fi

stage "[3] 校验并热重载 sshd(不断开现有连接)"
if sshd -t; then
    systemctl reload ssh 2>/dev/null \
        || systemctl reload sshd 2>/dev/null \
        || service ssh reload 2>/dev/null \
        || log "请手动重载 sshd"
    log "sshd 已重载"
else
    die "sshd 配置校验失败,未重载(现有连接不受影响);请检查 $SSHD_DROPIN"
fi

stage "[4] 客户端 ssh config(贴到你本地 ~/.ssh/config)"
SRV_FQDN="$(hostname -f 2>/dev/null || hostname)"
TS_IP="$(command -v tailscale >/dev/null 2>&1 && tailscale ip -4 2>/dev/null | head -1 || true)"
PUB_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
# awk 不提前 exit(避免 SIGPIPE + pipefail + set -e 把脚本掐掉),读完在 END 里输出
SSH_PORT="$(sshd -T 2>/dev/null | awk '/^port /{p=$2} END{print p}' || true)"; SSH_PORT="${SSH_PORT:-22}"
SRV_HOST="${CLAUDE_SSH_HOSTNAME:-$SRV_FQDN}"     # 可用 CLAUDE_SSH_HOSTNAME 指定(如公网 IP)
cat <<EOF

  Host ${USER_NAME}-claudevps
      HostName ${SRV_HOST}
      User ${USER_NAME}
      Port ${SSH_PORT}
      IdentityFile ~/.ssh/id_ed25519      # 改成你【私钥】的路径
      IdentitiesOnly yes

  # HostName 可选: ${SRV_FQDN} / ${TS_IP:-<tailscale>}(Tailscale,推荐) / ${PUB_IP:-<公网IP>}(公网)
  连接:  ssh ${USER_NAME}-claudevps
  验证:  ssh -v ${USER_NAME}-claudevps 'echo ok'   # 看是否走 publickey
EOF

stage "[5] 关闭 SSH 密码登录(默认;传 KEEP_PASSWORD=1 跳过)"
if [ "$KEEP_PASSWORD" = "1" ]; then
    log "KEEP_PASSWORD=1,保持密码登录不变"
elif [ -f "$SCRIPT_DIR/ssh_disable_password.sh" ]; then
    bash "$SCRIPT_DIR/ssh_disable_password.sh" \
        || log "关闭密码登录未完成(见上);公钥已加好,可稍后手动: sudo bash $SCRIPT_DIR/ssh_disable_password.sh"
else
    log "未找到 ssh_disable_password.sh,跳过;可手动关闭密码登录"
fi
