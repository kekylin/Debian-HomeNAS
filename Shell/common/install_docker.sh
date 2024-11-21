#!/bin/bash
# 使用北京外国语大学开源软件镜像站软件源安装Docker，根据系统版本进行不同处理

# 检查系统版本
source /etc/os-release

# 获取系统名称的函数
get_system_name() {
    [[ "$ID" == "debian" || "$ID" == "ubuntu" ]] && echo "$ID" || echo "unsupported"
}

# 获取系统名称
system_name=$(get_system_name)
if [[ "$system_name" == "unsupported" ]]; then
    echo "不支持的系统版本: $ID"
    exit 1
fi

# 安装依赖
apt-get update
apt-get install -y ca-certificates curl gnupg

# 信任 Docker 的 GPG 公钥并添加仓库
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://mirrors.bfsu.edu.cn/docker-ce/linux/$system_name/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://mirrors.bfsu.edu.cn/docker-ce/linux/$system_name \
  $VERSION_CODENAME stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 更新索引文件并安装 Docker 相关组件
apt-get update
apt-get -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 添加第一个创建的用户（ID：1000）至docker组
first_user=$(awk -F: '$3>=1000 && $1 != "nobody" {print $1}' /etc/passwd | sort | head -n 1)
usermod -aG docker "$first_user"

echo "Docker 安装已完成，用户 $first_user 已被添加到 docker 组中。"
