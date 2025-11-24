#!/bin/bash

echo "========================================"
echo "     Nginx 一键安装脚本（自动识别系统） "
echo "========================================"

# 检查是否为 root
if [ "$(id -u)" != "0" ]; then
   echo "❌ 请使用 root 用户运行此脚本！"
   exit 1
fi

# 检查系统类型
if [ -f /etc/redhat-release ]; then
    OS=centos
elif [ -f /etc/debian_version ]; then
    OS=debian
elif [ -f /etc/lsb-release ]; then
    OS=ubuntu
else
    echo "❌ 不支持的系统类型，请手动安装 Nginx"
    exit 1
fi

echo "系统识别为：$OS"
echo "开始安装依赖..."

if [ "$OS" = "centos" ]; then
    yum install -y epel-release
    yum install -y nginx
    systemctl enable nginx
    systemctl start nginx
elif [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    apt update
    apt install -y nginx
    systemctl enable nginx
    systemctl start nginx
fi

echo "========================================"
echo "✔ Nginx 安装并启动成功！"
echo "✔ 访问: http://服务器IP/"
echo "========================================"

