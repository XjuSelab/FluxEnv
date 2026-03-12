#!/bin/bash

echo "============================"
echo "   Nginx + Certbot 一键 HTTPS"
echo "============================"

# 检查是否 root 或 sudo
if [ "$EUID" -ne 0 ]; then
  echo "❌ 请使用 root 或 sudo 运行此脚本！"
  echo "例如：sudo ./install_https.sh"
  exit 1
fi

# 输入域名
read -p "请输入你的域名 (例如: example.com): " DOMAIN
if [ -z "$DOMAIN" ]; then
  echo "❌ 域名不能为空！退出脚本。"
  exit 1
fi

# 输入邮箱
read -p "请输入你的邮箱 (用于接收证书续期提醒): " EMAIL
if [ -z "$EMAIL" ]; then
  echo "❌ 邮箱不能为空！退出脚本。"
  exit 1
fi

echo "开始为域名 $DOMAIN 配置 HTTPS..."

# 安装 Nginx（如果未安装）
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
echo "   ✔ HTTPS 已成功启用！"
echo "   ➜ https://$DOMAIN"
echo "   ✔ Nginx 已自动配置证书"
echo "   ✔ Certbot 自动续期已启用"
echo "============================"

