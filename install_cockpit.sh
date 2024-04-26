#!/bin/bash

# 1. 安装Cockpit
# 启用向后移植存储库
. /etc/os-release
echo "deb http://deb.debian.org/debian ${VERSION_CODENAME}-backports main" | sudo tee /etc/apt/sources.list.d/backports.list
sudo apt update
# 安装或更新软件包
sudo apt install -t ${VERSION_CODENAME}-backports cockpit -y
# 安装cockpit-pcp
sudo apt install -t ${VERSION_CODENAME}-backports cockpit-pcp -y

# 2. 安装Cockpit附属组件
# 配置45Drives Repo安装脚本
curl -sSL https://repo.45drives.com/setup | sudo bash
sudo apt update
# 安装Navigator、File Sharing、Identities
sudo apt install cockpit-navigator cockpit-file-sharing cockpit-identities -y

# 安装官方组件
# 询问用户是否需要安装虚拟机组件
read -p "是否安装虚拟机组件？(y/n): " vm_install
if [[ $vm_install == "y" ]]; then
    sudo apt install -t ${VERSION_CODENAME}-backports cockpit-machines -y
fi

# 询问用户是否需要安装Podman容器组件
read -p "是否安装Podman容器组件？(y/n): " podman_install
if [[ $podman_install == "y" ]]; then
    sudo apt install -t ${VERSION_CODENAME}-backports cockpit-podman -y
fi

# 询问用户是否需要安装Cockpit ZFS管理器
read -p "是否安装Cockpit ZFS管理器？(y/n): " zfs_install
if [[ $zfs_install == "y" ]]; then
    # 安装ZFS依赖
    sudo apt update
    sudo apt install -y zfs-dkms zfsutils-linux
    # 克隆cockpit-zfs-manager仓库并复制到/usr/share/cockpit目录
    git clone https://github.com/optimans/cockpit-zfs-manager.git
    sudo cp -r cockpit-zfs-manager/zfs /usr/share/cockpit
fi
