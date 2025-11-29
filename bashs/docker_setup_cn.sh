#!/bin/bash

# 遇到错误时停止执行 (除特定容错命令外)
set -e

# 定义颜色方便查看
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}[1/6] 准备环境：安装必要的系统工具...${NC}"
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg lsb-release

echo -e "${GREEN}[2/6] 配置源：添加阿里云 GPG 密钥和仓库...${NC}"
# 创建密钥目录
sudo install -m 0755 -d /etc/apt/keyrings
# 下载阿里云 GPG 密钥 (覆盖旧的以防万一)
curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg --yes
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# 写入阿里云仓库地址
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://mirrors.aliyun.com/docker-ce/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

echo -e "${GREEN}[3/6] 开始安装：Docker Engine & Compose...${NC}"
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo -e "${GREEN}[4/6] 网络优化：配置国内镜像加速器...${NC}"
sudo mkdir -p /etc/docker
# 写入多个加速源，提高拉取成功率
sudo tee /etc/docker/daemon.json <<-'EOF'
{
  "registry-mirrors": [
    "https://docker.m.daocloud.io",
    "https://huecker.io",
    "https://dockerhub.timeweb.cloud",
    "https://noohub.ru"
  ]
}
EOF

echo -e "${GREEN}[5/6] 启动服务：重启 Docker 加载配置...${NC}"
sudo systemctl daemon-reload
sudo systemctl enable docker
sudo systemctl restart docker

echo -e "${GREEN}[6/6] 权限配置：设置当前用户免 sudo...${NC}"
sudo groupadd docker 2>/dev/null || true
sudo usermod -aG docker $USER

echo -e "\n${GREEN}==========================================${NC}"
echo -e "${GREEN}🎉 Docker 全套安装 & 配置完成！${NC}"
echo -e "${GREEN}Docker 版本：$(docker --version)${NC}"
echo -e "${GREEN}Compose 版本：$(docker compose version)${NC}"
echo -e "${GREEN}==========================================${NC}"
echo -e "${YELLOW}⚠️  重要提示：${NC}"
echo -e "${YELLOW}虽然安装已完成，但为了让权限生效，请你必须执行以下操作之一：${NC}"
echo -e "1. 执行命令: ${GREEN}newgrp docker${NC} (立即生效)"
echo -e "2. 或者: ${GREEN}注销并重新登录服务器${NC}"
