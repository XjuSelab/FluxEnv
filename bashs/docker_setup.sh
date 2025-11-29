#!/bin/bash

# 遇到错误立即停止
set -e

echo -e "\033[32m[1/5] 正在更新系统软件源...\033[0m"
sudo apt-get update

echo -e "\033[32m[2/5] 正在清理旧版本 Docker (如果存在)...\033[0m"
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do 
    sudo apt-get remove -y $pkg || true
done

echo -e "\033[32m[3/5] 安装必要的依赖组件...\033[0m"
sudo apt-get install -y ca-certificates curl gnupg

echo -e "\033[32m[4/5] 使用官方脚本一键安装 Docker & Docker Compose...\033[0m"
# 使用阿里云镜像加速安装脚本的下载（针对国内网络优化）
curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun

echo -e "\033[32m[5/5] 配置用户组 (免 sudo 使用)...\033[0m"
# 创建组（通常安装时已自动创建）并添加当前用户
sudo groupadd docker || true
sudo usermod -aG docker $USER

echo -e "\033[32m[+] 启用 Docker 开机自启...\033[0m"
sudo systemctl enable docker
sudo systemctl start docker

echo -e "\n\033[32m================================================\033[0m"
echo -e "\033[32m   🎉 Docker 安装完成！ \033[0m"
echo -e "\033[32m   版本信息：\033[0m"
docker --version
docker compose version
echo -e "\033[32m================================================\033[0m"
echo -e "\033[33m注意：为了让免 sudo 设置生效，请【注销并重新登录】服务器，或者运行命令：newgrp docker\033[0m"
