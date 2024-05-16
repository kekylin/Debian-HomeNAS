#!/bin/bash

# 设置 Docker 的apt存储库
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update

# 安装 Docker Engine、containerd 和 Docker Compose
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose

# 添加第一个创建的用户（ID：1000）至docker组
first_user=$(awk -F: '$3>=1000 && $1 != "nobody" {print $1}' /etc/passwd | sort | head -n 1)
usermod -aG docker "$first_user"

# 检查是否已经部署了同名容器
check_container_existence() {
    local container_name="$1"
    if docker ps -a --format "{{.Names}}" | grep -qFx "$container_name"; then
        echo "已经存在同名容器 '$container_name'，跳过部署操作。"
        return 0
    else
        return 1
    fi
}

# 部署Docker管理工具Portainer。
if ! check_container_existence "portainer"; then
    # 创建 Portainer Server 将使用的数据卷
    docker volume create portainer_data 2>/dev/null

    # 下载和安装 Portainer Server 容器
    docker run -d -p 8000:8000 -p 9443:9443 --name portainer --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce:latest
fi

# 部署Docker管理工具 Dockge
if ! check_container_existence "dockge"; then
    # 创建 stacks 和 dockge 目录
    sudo mkdir -p /opt/stacks /opt/dockge

    # 进入 Dockge 目录
    cd /opt/dockge || exit

    # 创建 Docker Compose 文件
    echo \
    "version: \"3.8\"
services:
  dockge:
    image: louislam/dockge:latest
    container_name: dockge
    restart: unless-stopped
    ports:
      - 5001:5001
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./data:/app/data
      - /opt/stacks:/opt/stacks
    environment:
      - DOCKGE_STACKS_DIR=/opt/stacks" | \
    sudo tee docker-compose.yml > /dev/null

    # 运行部署命令
    sudo docker compose up -d
fi
