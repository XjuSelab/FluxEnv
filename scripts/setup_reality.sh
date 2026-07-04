#!/bin/bash

# setup_reality.sh —— 一键部署 VLESS + XTLS-Vision + REALITY (Xray)。
#
# 当下最快、免域名/证书、抗封锁的代理方案,产出可直接导入 v2rayN 的 vless:// 链接。
# 脚本把"选偷跑目标 → 生成密钥 → 写配置 → 启用 → 端到端自测 → 出链接"全流程封装,
# 并内置本仓库踩过的关键坑:
#   Xray 26.x REALITY 有 8192 字节硬上限,偷跑目标(dest)的 TLS 证书记录超限就报
#   "handshake did not complete successfully",密钥全对也连不上(XTLS issue #6356)。
#   www.microsoft.com 证书记录 8273B 直接挂。故脚本自动测量候选证书链大小 + 逐个
#   握手自测,只采用真正能连通的目标。
#
# 在目标 VPS 上以 root 运行(Ubuntu/Debian):
#   sudo bash scripts/setup_reality.sh                 # 全自动:装 xray + 自动选优 dest + 出链接
#   sudo bash scripts/setup_reality.sh install         # 同上(默认动作)
#   sudo bash scripts/setup_reality.sh link            # 只读:重新打印已有配置的分享链接
#   sudo bash scripts/setup_reality.sh probe           # 只测候选 dest 证书大小,不改配置
#   sudo bash scripts/setup_reality.sh cleanup         # 停用 xray 并还原最近一次备份
#
# 环境变量(可选):
#   REALITY_PORT=443            监听端口
#   REALITY_DEST=www.tesla.com  指定偷跑目标(跳过自动选优,仍会自测)
#   REALITY_UUID=<uuid>         指定 UUID(默认复用已有或新生成)
#   REALITY_IP=<ip>             分享链接里的地址(默认取公网出口 IP,NAT 机可手动指定)
#   REALITY_LABEL=<名字>        节点备注名(默认 <主机名>-Reality)
#   REALITY_FORCE=1             即使已有 reality 配置也重建(换新密钥,会使旧链接失效)

set -euo pipefail

# ---------------- 可调参数 ----------------
PORT="${REALITY_PORT:-443}"
DEST_OVERRIDE="${REALITY_DEST:-}"
UUID_OVERRIDE="${REALITY_UUID:-}"
LABEL="${REALITY_LABEL:-$(hostname)-Reality}"
FORCE="${REALITY_FORCE:-0}"
IP_OVERRIDE="${REALITY_IP:-}"

XRAY_CONF="/usr/local/etc/xray/config.json"
SHARE_FILE="/usr/local/etc/xray/reality-share.txt"
SELFTEST_SOCKS=20808
DER_MAX=5500   # DER 链上限:留足 OCSP/SCT 开销,避免撞 REALITY 8192 硬限(microsoft 5879 就挂)

# 候选偷跑目标:证书链小、不被 GFW 按 SNI 阻断、不在 xray 的 apple/icloud 告警名单。
CANDIDATES=(www.tesla.com www.samsung.com www.nvidia.com addons.mozilla.org www.amazon.com www.lovelive-anime.jp)

ACTION="${1:-install}"

# ---------------- 输出 helper ----------------
init_colors() {
    if [ -t 1 ]; then
        GREEN=$(printf '\033[32m'); YELLOW=$(printf '\033[33m')
        RED=$(printf '\033[31m'); BOLD=$(printf '\033[1m'); RESET=$(printf '\033[m')
    else
        GREEN=""; YELLOW=""; RED=""; BOLD=""; RESET=""
    fi
}
stage()    { printf '\n%s=== %s ===%s\n' "$BOLD" "$*" "$RESET"; }
progress() { printf '  → %s\n' "$*"; }
ok()       { printf '  %s✓%s %s\n' "$GREEN" "$RESET" "$*"; }
warn()     { printf '%s警告: %s%s\n' "$YELLOW" "$*" "$RESET" >&2; }
die()      { printf '%s错误: %s%s\n' "$RED" "$*" "$RESET" >&2; exit 1; }

need_root() { [ "$(id -u)" -eq 0 ] || die "请用 sudo/root 运行"; }

# ---------------- 依赖与 xray ----------------
install_prereqs() {
    local miss=()
    for c in curl openssl jq; do command -v "$c" >/dev/null || miss+=("$c"); done
    if [ "${#miss[@]}" -gt 0 ]; then
        progress "安装依赖: ${miss[*]}"
        apt-get update -qq && apt-get install -y -qq "${miss[@]}" >/dev/null
    fi
    command -v qrencode >/dev/null || apt-get install -y -qq qrencode >/dev/null 2>&1 || true
}

ensure_xray() {
    if command -v xray >/dev/null; then
        ok "xray 已安装: $(xray version 2>/dev/null | head -1)"
        return
    fi
    progress "安装 Xray-core (官方脚本)…"
    bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install >/dev/null 2>&1 \
        || die "Xray 安装失败(检查网络/GitHub 连通)"
    command -v xray >/dev/null || die "Xray 安装后仍找不到可执行文件"
    ok "xray 安装完成: $(xray version 2>/dev/null | head -1)"
}

# ---------------- 身份(uuid / 密钥 / shortId) ----------------
pub_from_priv() { xray x25519 -i "$1" 2>/dev/null | grep -i public | sed 's/.*: //' | tr -d '[:space:]'; }

reuse_identity() {
    # 已有 reality 配置且未 FORCE 时复用,不改动现网,避免旧链接失效。
    [ -f "$XRAY_CONF" ] || return 1
    [ "$FORCE" = "1" ] && return 1
    local sec; sec=$(jq -r '.inbounds[0].streamSettings.security // empty' "$XRAY_CONF" 2>/dev/null || true)
    [ "$sec" = "reality" ] || return 1
    UUID=$(jq -r '.inbounds[0].settings.clients[0].id // empty' "$XRAY_CONF")
    PRIV=$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey // empty' "$XRAY_CONF")
    SID=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0] // empty' "$XRAY_CONF")
    DEST=$(jq -r '.inbounds[0].streamSettings.realitySettings.dest // empty' "$XRAY_CONF" | sed 's/:[0-9]*$//')
    SNI=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0] // empty' "$XRAY_CONF")
    PORT=$(jq -r '.inbounds[0].port // empty' "$XRAY_CONF")
    [ -n "$UUID" ] && [ -n "$PRIV" ] && [ -n "$SNI" ] && [ -n "$PORT" ] || return 1
    PUB=$(pub_from_priv "$PRIV")
    [ -n "$PUB" ] || return 1
    return 0
}

gen_identity() {
    UUID="${UUID_OVERRIDE:-$(xray uuid)}"
    local keyout; keyout=$(xray x25519)
    PRIV=$(echo "$keyout" | grep -i private | sed 's/.*: //' | tr -d '[:space:]')
    PUB=$(echo "$keyout"  | grep -i public  | sed 's/.*: //' | tr -d '[:space:]')
    SID=$(openssl rand -hex 8)
    [ -n "$PRIV" ] && [ -n "$PUB" ] && [ -n "$UUID" ] && [ -n "$SID" ] || die "密钥/UUID 生成失败"
}

# ---------------- dest 证书链测量 ----------------
# 输出该目标的 DER 证书链字节数;无 h2 或不可达则输出 -1。
dest_der() {
    local d="$1" tmp der=0 s
    tmp=$(mktemp -d)
    echo | timeout 8 openssl s_client -connect "$d:443" -servername "$d" -tls1_3 -alpn h2 -showcerts >"$tmp/o" 2>/dev/null || true
    if ! grep -q "ALPN protocol: h2" "$tmp/o"; then rm -rf "$tmp"; echo "-1"; return; fi
    csplit -sz -f "$tmp/c" -b "%02d.pem" "$tmp/o" "/-----BEGIN CERTIFICATE-----/" "{*}" 2>/dev/null || true
    for c in "$tmp"/c*.pem; do
        [ -f "$c" ] || continue
        s=$(openssl x509 -in "$c" -outform der 2>/dev/null | wc -c)
        [ "$s" -gt 0 ] && der=$((der + s))
    done
    rm -rf "$tmp"
    [ "$der" -gt 0 ] && echo "$der" || echo "-1"
}

# ---------------- 写服务端配置 ----------------
write_config() {
    local dest="$1" sni="$2" tmp out
    tmp=$(mktemp --suffix=.json)   # xray 靠 .json 扩展名判断配置格式,不能用裸 mktemp
    cat > "$tmp" <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": $PORT,
      "protocol": "vless",
      "settings": {
        "clients": [ { "id": "$UUID", "flow": "xtls-rprx-vision" } ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "$dest:443",
          "xver": 0,
          "serverNames": ["$sni"],
          "privateKey": "$PRIV",
          "shortIds": ["$SID", ""]
        }
      },
      "sniffing": { "enabled": true, "destOverride": ["http", "tls", "quic"] }
    }
  ],
  "outbounds": [
    { "protocol": "freedom", "tag": "direct" },
    { "protocol": "blackhole", "tag": "block" }
  ]
}
EOF
    if ! out=$(xray -test -config "$tmp" 2>&1); then
        rm -f "$tmp"
        die "生成的配置未通过 xray -test: $(echo "$out" | tail -2)"
    fi
    [ -f "$XRAY_CONF" ] && cp "$XRAY_CONF" "${XRAY_CONF}.bak.$(date +%s)"
    install -m 644 "$tmp" "$XRAY_CONF"
    rm -f "$tmp"
}

# ---------------- 端到端握手自测 ----------------
# 本机起临时客户端拨自己,经 socks 出口访问 generate_204;返回 204 即隧道打通。
selftest() {
    local cli pid code
    cli=$(mktemp --suffix=.json)   # 同理:客户端配置也要 .json 扩展名
    cat > "$cli" <<EOF
{
  "log": {"loglevel": "error"},
  "inbounds": [{"port": $SELFTEST_SOCKS, "listen": "127.0.0.1", "protocol": "socks", "settings": {"udp": false}}],
  "outbounds": [{
    "protocol": "vless",
    "settings": {"vnext": [{"address": "127.0.0.1", "port": $PORT, "users": [{"id": "$UUID", "flow": "xtls-rprx-vision", "encryption": "none"}]}]},
    "streamSettings": {"network": "tcp", "security": "reality",
      "realitySettings": {"serverName": "$SNI", "fingerprint": "chrome", "publicKey": "$PUB", "shortId": "$SID"}}
  }]
}
EOF
    xray run -c "$cli" >/dev/null 2>&1 &
    pid=$!
    sleep 3
    code=$(curl -s --max-time 10 --socks5-hostname "127.0.0.1:$SELFTEST_SOCKS" \
        -o /dev/null -w '%{http_code}' https://www.gstatic.com/generate_204 2>/dev/null || true)
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    rm -f "$cli"
    [ "$code" = "204" ]
}

# ---------------- 自动选优 dest ----------------
pick_dest() {
    local d der
    for d in "$@"; do
        der=$(dest_der "$d")
        if [ "$der" -le 0 ]; then progress "跳过 $d (无 h2 或不可达)"; continue; fi
        if [ "$der" -gt "$DER_MAX" ]; then progress "跳过 $d (证书链 ${der}B > ${DER_MAX}B,有撞 8192 风险)"; continue; fi
        progress "试 $d (证书链 ${der}B) …"
        DEST="$d"; SNI="$d"
        write_config "$DEST" "$SNI"
        systemctl restart xray; sleep 1
        if selftest; then ok "$d 握手自测通过,采用"; return 0; fi
        progress "$d 自测失败,换下一个"
    done
    return 1
}

# ---------------- 分享链接 ----------------
detect_ip() {
    SERVER_IP="$IP_OVERRIDE"
    [ -n "$SERVER_IP" ] || SERVER_IP=$(curl -s --max-time 8 https://api.ipify.org 2>/dev/null || true)
    [ -n "$SERVER_IP" ] || SERVER_IP=$(ip -4 addr show scope global 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -1)
    [ -n "$SERVER_IP" ] || die "无法确定服务器 IP,请用 REALITY_IP=<ip> 指定"
}

build_link() {
    LINK="vless://${UUID}@${SERVER_IP}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=chrome&pbk=${PUB}&sid=${SID}&type=tcp&headerType=none#${LABEL}"
}

emit() {
    detect_ip
    build_link
    { echo "$LINK"; } > "$SHARE_FILE"
    stage "部署完成"
    printf '  地址:端口   %s:%s\n' "$SERVER_IP" "$PORT"
    printf '  UUID       %s\n' "$UUID"
    printf '  流控        xtls-rprx-vision\n'
    printf '  security   reality   SNI/dest  %s\n' "$SNI"
    printf '  PublicKey  %s\n' "$PUB"
    printf '  ShortId    %s\n' "$SID"
    printf '  Fingerprint chrome\n'
    printf '\n%sv2rayN 导入链接%s (已存 %s):\n' "$BOLD" "$RESET" "$SHARE_FILE"
    printf '%s\n' "$LINK"
    if command -v qrencode >/dev/null; then
        printf '\n扫码导入:\n'
        qrencode -t ANSIUTF8 "$LINK" 2>/dev/null || true
    fi
}

# ==================== 动作 ====================
init_colors

case "$ACTION" in
    probe)
        need_root; install_prereqs
        stage "测量候选 dest 证书链 (上限 ${DER_MAX}B)"
        for d in "${CANDIDATES[@]}"; do
            der=$(dest_der "$d")
            if [ "$der" -le 0 ]; then printf '  %-22s 无 h2 / 不可达\n' "$d"
            elif [ "$der" -gt "$DER_MAX" ]; then printf '  %-22s %sB  %s✗ 超限%s\n' "$d" "$der" "$RED" "$RESET"
            else printf '  %-22s %sB  %s✓%s\n' "$d" "$der" "$GREEN" "$RESET"; fi
        done
        ;;

    link)
        need_root; install_prereqs
        reuse_identity || die "未找到可用的 reality 配置(先跑 install)"
        emit
        ;;

    cleanup)
        need_root
        stage "停用 xray 并还原备份"
        systemctl stop xray 2>/dev/null || true
        systemctl disable xray 2>/dev/null || true
        latest=$(ls -1t "${XRAY_CONF}".bak.* 2>/dev/null | head -1 || true)
        if [ -n "$latest" ]; then cp "$latest" "$XRAY_CONF"; ok "已还原 $latest"; else warn "无备份可还原"; fi
        ok "xray 已停用(如需彻底卸载: xray 官方脚本 @ remove)"
        ;;

    install)
        need_root
        install_prereqs
        ensure_xray
        if reuse_identity; then
            stage "检测到已有 REALITY 配置,复用密钥(如需重建加 REALITY_FORCE=1)"
            ok "UUID $UUID  dest $DEST"
            write_config "$DEST" "$SNI"
            systemctl enable xray >/dev/null 2>&1 || true
            systemctl restart xray; sleep 1
            stage "端到端自测"
            if selftest; then ok "隧道自测通过"; else warn "自测未通过(可能公网 443 被占/被墙,链接仍照出)"; fi
        else
            gen_identity
            stage "自动挑选偷跑目标 (dest)"
            if [ -n "$DEST_OVERRIDE" ]; then
                DEST="$DEST_OVERRIDE"; SNI="$DEST_OVERRIDE"
                progress "使用指定 dest: $DEST"
                write_config "$DEST" "$SNI"; systemctl restart xray; sleep 1
                selftest || die "指定的 dest=$DEST 自测失败(证书可能超 8192 或不支持 TLS1.3/h2)"
                ok "$DEST 自测通过"
            else
                pick_dest "${CANDIDATES[@]}" || die "所有候选 dest 均未通过自测,请手动指定 REALITY_DEST"
            fi
            systemctl enable xray >/dev/null 2>&1 || true
        fi
        emit
        ;;

    *)
        die "未知动作 '$ACTION'(install|link|probe|cleanup)"
        ;;
esac
