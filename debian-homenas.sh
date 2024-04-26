#!/bin/bash

# 安装必备软件
apt update
apt install -y sudo curl git vim net-tools

# 添加第一个创建的用户至sudo组
user_name=$(getent passwd | awk -F: '$3>=1000{print $1}' | head -n 1)
usermod -aG sudo $user_name

# 更换国内镜像源
cp /etc/apt/sources.list /etc/apt/sources.list.bak

# 检测当前Debian系统的发行版本
debian_version=$(lsb_release -cs)

# 根据不同的发行版本选择相应的源
case $debian_version in
    "bookworm")
        mirror="https://mirrors.tuna.tsinghua.edu.cn/debian/"
        ;;
    "bullseye")
        mirror="https://mirrors.tuna.tsinghua.edu.cn/debian/"
        ;;
    "buster")
        mirror="https://mirrors.tuna.tsinghua.edu.cn/debian/"
        ;;
    *)
        echo "Unsupported Debian version."
        exit 1
        ;;
esac

# 替换软件源配置文件内容
cat << EOF > /etc/apt/sources.list
deb $mirror $debian_version main contrib non-free
deb $mirror $debian_version-updates main contrib non-free
deb $mirror $debian_version-backports main contrib non-free
# 使用默认的安全源
EOF

apt update
apt install -y apt-transport-https ca-certificates
apt update && apt upgrade -y
