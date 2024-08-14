#!/bin/bash
# 使用清华镜像源安装Docker

# 安装依赖
apt-get update
apt-get install ca-certificates curl gnupg

# 信任 Docker 的 GPG 公钥并添加仓库
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/debian \
  "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null
  
# 更新索引文件并安装 Docker 相关组件
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 添加第一个创建的用户（ID：1000）至docker组
first_user=$(awk -F: '$3>=1000 && $1 != "nobody" {print $1}' /etc/passwd | sort | head -n 1)
usermod -aG docker "$first_user"
