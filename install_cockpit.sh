#!/bin/bash

# 启用向后移植存储库
echo "deb http://deb.debian.org/debian $(. /etc/os-release && echo $VERSION_CODENAME)-backports main" > /etc/apt/sources.list.d/backports.list
apt update

# 配置45Drives Repo安装脚本并安装Navigator、File Sharing、Identities组件
curl -sSL https://repo.45drives.com/setup | bash
apt update
apt install -y cockpit-navigator cockpit-file-sharing cockpit-identities

# 安装Cockpit及其附属组件
apt install -y -t $(. /etc/os-release && echo $VERSION_CODENAME)-backports cockpit cockpit-pcp

# 安装官方组件
components=("cockpit-machines" "cockpit-podman")
for component in "${components[@]}"; do
    read -p "是否安装${component}组件？(y/n): " install_component
    if [[ $install_component == "y" ]]; then
        apt install -y -t $(. /etc/os-release && echo $VERSION_CODENAME)-backports $component
    fi
done

# 询问是否安装Cockpit ZFS管理器
read -p "是否安装Cockpit ZFS管理器？(y/n): " install_zfs_manager
if [[ $install_zfs_manager == "y" ]]; then
    apt update
    apt install -y zfs-dkms zfsutils-linux git
    git clone https://github.com/optimans/cockpit-zfs-manager.git
    cp -r cockpit-zfs-manager/zfs /usr/share/cockpit
fi
