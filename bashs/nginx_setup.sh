#!/bin/bash
echo "========================================"
echo "     Nginx 一键安装脚本（自动识别系统） "
echo "========================================"

# 必须 root 才能运行
if [ "$EUID" -ne 0 ]; then
    echo "❌ 请使用 root 用户运行此脚本：sudo bash nginx_setup.sh"
    exit 1
fi

# 识别系统
OS="unknown"

if grep -qi "raspbian" /etc/os-release; then
    OS="raspbian"
elif grep -qi "ubuntu" /etc/os-release; then
    OS="ubuntu"
elif grep -qi "debian" /etc/os-release; then
    OS="debian"
elif grep -qi "centos" /etc/os-release; then
    OS="centos"
fi

echo "➡ 检测到系统：$OS"

# 已安装检测
if command -v nginx >/dev/null 2>&1; then
    echo "✔ Nginx 已安装：$(nginx -v 2>&1)"
    echo "✔ 如需重启: systemctl restart nginx"
    exit 0
fi

echo "➡ 开始安装依赖..."

case "$OS" in
    centos)
        yum install -y epel-release
        yum install -y nginx
        systemctl enable nginx
        systemctl start nginx
        ;;

    debian|ubuntu|raspbian)
        apt update
        apt install -y nginx
        systemctl enable nginx
        systemctl start nginx
        ;;

    *)
        echo "❌ 不支持的系统，请手动安装 Nginx"
        exit 1
        ;;
esac

echo "========================================"
echo "🎉 Nginx 安装并启动成功!"
echo "✔ 状态: systemctl status nginx"
echo "✔ 访问: http://服务器IP/"
echo "========================================"

