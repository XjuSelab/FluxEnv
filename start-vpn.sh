#!/bin/bash
# === Xray 一键开启 VPN 脚本 ===
# 使用方式: source ~/start_vpn.sh

unset HTTP_PROXY HTTPS_PROXY NO_PROXY

XRAY_BIN="/usr/local/bin/xray"
XRAY_CONF="/usr/local/etc/xray/config.json"
XRAY_LOG="$HOME/xray.log" # 日志文件存储位置

HTTP_PROXY_PORT=10810
SOCKS_PROXY_PORT=10809

touch "$XRAY_LOG"

# 检查 xray 是否存在
if [ ! -x "$XRAY_BIN" ]; then
  echo "❌ 未找到 Xray 可执行文件: $XRAY_BIN"
  return 1
fi

# 检查配置文件
if [ ! -f "$XRAY_CONF" ]; then
  echo "❌ 未找到配置文件: $XRAY_CONF"
  return 1
fi

# 停止旧进程
pkill -f "$XRAY_BIN run" >/dev/null 2>&1

# 启动 Xray 后台进程
nohup "$XRAY_BIN" run -c "$XRAY_CONF" >"$XRAY_LOG" 2>&1 &
sleep 1

# 检查是否成功启动
if pgrep -x "xray" >/dev/null; then
  echo "✅ Xray 已启动"
else
  echo "❌ 启动失败，请检查日志: $XRAY_LOG"
  return 1
fi

# 设置代理环境变量
export http_proxy="http://127.0.0.1:${HTTP_PROXY_PORT}"
export https_proxy="http://127.0.0.1:${HTTP_PROXY_PORT}"
export all_proxy="socks5://127.0.0.1:${SOCKS_PROXY_PORT}"

echo "🌐 已设置全局代理:"
echo "  http_proxy=$http_proxy"
echo "  https_proxy=$https_proxy"
echo "  all_proxy=$all_proxy"

# 测试出口 IP
echo -e "\n🔍 检测出口 IP..."
curl -s --max-time 10 https://ipinfo.io | jq '{ip, country, org}' 2>/dev/null || curl -s --max-time 10 https://ipinfo.io/ip

echo "✅ VPN 已开启完成！"

curl -s --max-time 5 google.com >/dev/null && echo "✅ 外网连接成功" || echo "⚠️ 外网仍不可达"
