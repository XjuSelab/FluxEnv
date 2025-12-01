#!/bin/bash

# 颜色定义，用于输出美化
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo -e "${GREEN}>>> 开始更新软件包列表...${NC}"
sudo apt-get update

echo -e "${GREEN}>>> 正在安装 OpenJDK 17 (Spring Boot 推荐版本)...${NC}"
sudo apt-get install -y openjdk-17-jdk

echo -e "${GREEN}>>> 正在安装 Maven...${NC}"
sudo apt-get install -y maven

echo -e "${GREEN}>>> 验证安装结果...${NC}"
echo "------------------------------------------------"
echo "Java Version:"
java -version
echo "------------------------------------------------"
echo "Maven Version:"
mvn -v
echo "------------------------------------------------"

echo -e "${GREEN}>>> 安装完成！你现在可以运行 Spring Boot 项目了。${NC}"
