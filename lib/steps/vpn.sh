#!/bin/bash

write_default_xray_config() {
    write_file /usr/local/etc/xray/config.json "0644" "" <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    { "port": 10809, "listen": "127.0.0.1", "protocol": "socks", "settings": { "auth": "noauth" } },
    { "port": 10810, "listen": "127.0.0.1", "protocol": "http", "settings": { "timeout": 0 } }
  ],
  "outbounds": [
    {
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "${VPN_DOMAIN}",
            "port": 443,
            "users": [
              {
                "id": "${VPN_UUID}",
                "encryption": "none",
                "flow": "xtls-rprx-vision"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": { "serverName": "${VPN_DOMAIN}" }
      }
    }
  ]
}
EOF
}

write_vpn_launcher() {
    local target_script="$1"
    write_file "$target_script" "0755" "" <<'EOF'
#!/bin/bash
unset HTTP_PROXY HTTPS_PROXY NO_PROXY

XRAY_BIN="/usr/local/bin/xray"
XRAY_CONF="/usr/local/etc/xray/config.json"
XRAY_LOG="$HOME/xray.log"

HTTP_PROXY_PORT=10810
SOCKS_PROXY_PORT=10809

if [ ! -x "$XRAY_BIN" ]; then
    echo "❌ 未找到 Xray 可执行文件: $XRAY_BIN"
    return 1 2>/dev/null || exit 1
fi

if [ ! -f "$XRAY_CONF" ]; then
    echo "❌ 未找到配置文件: $XRAY_CONF"
    return 1 2>/dev/null || exit 1
fi

pkill -f "$XRAY_BIN run" >/dev/null 2>&1 || true
nohup "$XRAY_BIN" run -c "$XRAY_CONF" >"$XRAY_LOG" 2>&1 &
sleep 1

export http_proxy="http://127.0.0.1:${HTTP_PROXY_PORT}"
export https_proxy="http://127.0.0.1:${HTTP_PROXY_PORT}"
export all_proxy="socks5://127.0.0.1:${SOCKS_PROXY_PORT}"

echo "✅ Xray 已启动"
echo "http_proxy=$http_proxy"
echo "https_proxy=$https_proxy"
echo "all_proxy=$all_proxy"
EOF
}

write_vpn_stopper() {
    local target_script="$1"
    write_file "$target_script" "0755" "" <<'EOF'
#!/bin/bash
unset HTTP_PROXY HTTPS_PROXY NO_PROXY
pkill -f "/usr/local/bin/xray run" >/dev/null 2>&1 || true
unset http_proxy https_proxy all_proxy
echo "🛑 Xray 已关闭，环境变量已清除"
EOF
}

step_vpn() {
    stage "Xray VPN 配置"

    resolve_toggle ENABLE_VPN "是否配置 Xray VPN？" "n"
    VPN_ENABLED="$ENABLE_VPN"
    if [ "$VPN_ENABLED" -ne 1 ]; then
        progress "跳过 VPN 配置"
        return 0
    fi

    if [ -z "$XRAY_ARCHIVE" ]; then
        warn "当前架构没有对应的 Xray 资源"
        return 0
    fi

    local archive_path=""
    if [ -f "$FLUXENV_ROOT/$XRAY_ARCHIVE" ]; then
        archive_path="$FLUXENV_ROOT/$XRAY_ARCHIVE"
    elif [ -f "$OFFLINE_DIR/$XRAY_ARCHIVE" ]; then
        archive_path="$OFFLINE_DIR/$XRAY_ARCHIVE"
    fi

    if [ -z "$archive_path" ]; then
        warn "未找到离线 Xray 资源: $XRAY_ARCHIVE"
        return 0
    fi

    run_cmd "解压 Xray 资源" unzip -o "$archive_path" -d /usr/local/xray
    run_cmd "安装 Xray 到系统路径" install -m 0755 /usr/local/xray/xray /usr/local/bin/xray
    run_shell "复制 geo 数据文件" "mkdir -p /usr/local/share/xray && cp -f /usr/local/xray/geo* /usr/local/share/xray/ 2>/dev/null || true"
    run_cmd "创建 Xray 配置目录" mkdir -p /usr/local/etc/xray

    prompt_value VPN_DOMAIN "请输入 VPN 服务器域名" '.+'
    prompt_value VPN_UUID "请输入 VPN 用户 UUID" '^[0-9a-fA-F-]{32,}$'
    write_default_xray_config

    run_cmd "创建 VPN 脚本目录" mkdir -p "$TARGET_HOME/bin"
    write_vpn_launcher "$TARGET_HOME/bin/start-vpn"
    write_vpn_stopper "$TARGET_HOME/bin/stop-vpn"

    if [ "$TARGET_USER" != "root" ] && [ "${DRY_RUN:-0}" -eq 0 ]; then
        chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/bin"
    fi

    VPN_INSTALLED=1
}
