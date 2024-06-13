#!/bin/bash

# 使用华为镜像源安装Docker
# 安装依赖
apt-get install ca-certificates curl gnupg
# 信任 Docker 的 GPG 公钥并添加仓库
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://mirrors.huaweicloud.com/docker-ce/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://mirrors.huaweicloud.com/docker-ce/linux/debian \
  "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null
# 更新索引文件并安装 Docker 相关组件
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 添加第一个创建的用户（ID：1000）至docker组
first_user=$(awk -F: '$3>=1000 && $1 != "nobody" {print $1}' /etc/passwd | sort | head -n 1)
usermod -aG docker "$first_user"

# 检查是否已经部署了同名容器
check_container_existence() {
    docker ps -a --format "{{.Names}}" | grep -qFx "$1"
}

# 询问用户需要安装哪些组件
echo "选择安装Docker管理工具: 
1) Portainer 
2) Dockge 
3) 全部安装 
0) 不安装 (默认: 0)"
read -p "请输入选择: " install_choice
install_choice=${install_choice:-0}

# 设置安装标志
install_portainer=false
install_dockge=false

case "$install_choice" in
    1) install_portainer=true ;;
    2) install_dockge=true ;;
    3) install_portainer=true; install_dockge=true ;;
esac

# 安装 Docker 管理工具 Portainer
if $install_portainer; then
    if check_container_existence "portainer"; then
        echo "Portainer 容器已经存在，跳过安装。"
    else
        docker volume create portainer_data 2>/dev/null
        docker run -d -p 8000:8000 -p 9443:9443 --name portainer --restart=always \
            -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data \
            portainer/portainer-ce:latest
    fi
else
    echo "跳过 Portainer 安装。"
fi

# 安装 Docker 管理工具 Dockge
if $install_dockge; then
    if check_container_existence "dockge"; then
        echo "Dockge 容器已经存在，跳过安装。"
    else
        sudo mkdir -p /opt/stacks /opt/dockge
        cd /opt/dockge || exit

        # 创建 Docker Compose 文件
        sudo tee docker-compose.yml > /dev/null <<EOF
services:
  dockge:
    image: louislam/dockge:1
    restart: unless-stopped
    ports:
      # Host Port : Container Port
      - 5001:5001
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./data:/app/data
        
      # If you want to use private registries, you need to share the auth file with Dockge:
      # - /root/.docker/:/root/.docker

      # Stacks Directory
      # ⚠️ READ IT CAREFULLY. If you did it wrong, your data could end up writing into a WRONG PATH.
      # ⚠️ 1. FULL path only. No relative path (MUST)
      # ⚠️ 2. Left Stacks Path === Right Stacks Path (MUST)
      - /opt/stacks:/opt/stacks
    environment:
      # Tell Dockge where is your stacks directory
      - DOCKGE_STACKS_DIR=/opt/stacks
EOF

        sudo docker compose up -d
    fi
else
    echo "跳过 Dockge 安装。"
fi
