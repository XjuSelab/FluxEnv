#!/bin/bash

echo "============================"
echo "   Nginx + Certbot 一键 HTTPS"
echo "============================"

# 输入域名
read -p "请输入你的域名(例如: example.com): " DOMAIN

if [ -z "$DOMAIN" ]; then
  echo "❌ 域名不能为空！退出脚本。"
  exit 1
fi

# 输入邮箱
read -p "请输入你的邮箱(用于接收证书续期通知): " EMAIL

if [ -z "$EMAIL" ]; then
  echo "❌ 邮箱不能为空！退出脚本。"
  exit 1
fi

echo "开始为域名 $DOMAIN 申请证书..."

# 确保 Nginx 已安装
if ! command -v nginx >/dev/null 2>&1; then
    echo "检测到 Nginx 未安装，正在安装..."
    apt update && apt install -y nginx
fi

# 安装 Certbot
echo "安装 Certbot..."
apt update
apt install -y certbot python3-certbot-nginx

# 申请证书
echo "申请证书中..."
certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$EMAIL" --redirect

echo "============================"
echo "    ✔ HTTPS 已成功启用！"
echo "    https://$DOMAIN"
echo "    证书自动续期已配置"
echo "============================"

