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


# 配置Docker镜像加速地址
MIRRORS=("https://docker.1panel.live" "https://hub.iyuu.cn")
DAEMON_JSON="/etc/docker/daemon.json"

# 函数：将数组转换为 JSON 数组字符串
array_to_json_array() {
  local arr=("$@")
  local json_array="[\n"
  local len=${#arr[@]}
  for ((i = 0; i < len; i++)); do
    json_array+="    \"${arr[i]}\""
    [[ $i -lt $((len - 1)) ]] && json_array+=","
    json_array+="\n"
  done
  json_array+="  ]"
  echo -e "$json_array"
}

# 函数：更新配置文件中的 registry-mirrors
update_registry_mirrors() {
  local new_mirrors=("$@")
  local existing_mirrors=()

  # 读取现有的镜像地址
  [ -f "$DAEMON_JSON" ] && existing_mirrors=($(grep -oP '"https?://[^"]+"' "$DAEMON_JSON" | tr -d '"'))

  # 添加新镜像地址，避免重复
  for mirror in "${new_mirrors[@]}"; do
    [[ ! " ${existing_mirrors[*]} " =~ " ${mirror} " ]] && existing_mirrors+=("$mirror")
  done

  # 生成新的 JSON 内容
  local updated_mirrors_json
  updated_mirrors_json=$(array_to_json_array "${existing_mirrors[@]}")

  # 更新配置文件
  echo -e "{\n  \"registry-mirrors\": $updated_mirrors_json\n}" > "$DAEMON_JSON"
}

# 主逻辑
read -p "是否配置Docker镜像加速地址？(y/n): " choice
if [[ "$choice" =~ ^[Yy]$ ]]; then
  update_registry_mirrors "${MIRRORS[@]}"
  systemctl daemon-reload
  systemctl restart docker
  echo "Docker镜像加速地址配置已完成。"
else
  echo "跳过Docker镜像加速地址配置。"
fi
