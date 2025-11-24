#!/bin/bash
# === 关闭 Xray VPN 并清除代理变量 ===

unset HTTP_PROXY HTTPS_PROXY NO_PROXY

pkill -f "/usr/local/bin/xray run"
unset http_proxy https_proxy all_proxy

echo "🛑 Xray 已关闭，环境变量已清除"
