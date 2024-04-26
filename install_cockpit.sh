#!/bin/bash

# 启用向后移植存储库
echo "deb http://deb.debian.org/debian $(. /etc/os-release && echo $VERSION_CODENAME)-backports main" > /etc/apt/sources.list.d/backports.list
# 配置45Drives Repo安装脚本并安装Navigator、File Sharing、Identities组件
curl -sSL https://repo.45drives.com/setup | bash
apt update

# 安装Cockpit及其附属组件
apt install -y -t $(. /etc/os-release && echo $VERSION_CODENAME)-backports cockpit cockpit-pcp
apt install -y cockpit-navigator cockpit-file-sharing cockpit-identities

# 询问是否安装cockpit-machines
read -p "是否安装cockpit-machines组件？(y/n): " install_machines
if [[ $install_machines == "y" ]]; then
    to_install+=("cockpit-machines")
fi

# 询问是否安装cockpit-podman
read -p "是否安装cockpit-podman组件？(y/n): " install_podman
if [[ $install_podman == "y" ]]; then
    to_install+=("cockpit-podman")
fi

# 根据用户回答安装组件
for component in "${to_install[@]}"; do
    apt install -y -t $(. /etc/os-release && echo $VERSION_CODENAME)-backports "$component"
done
