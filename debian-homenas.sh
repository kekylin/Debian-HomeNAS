#!/bin/bash

# 安装必备软件
apt update
apt install -y sudo curl git vim wget
apt install -y apt-transport-https ca-certificates
# 添加第一个创建的用户至sudo组
user_name=$(getent passwd | awk -F: '$3>=1000{print $1}' | head -n 1)
usermod -aG sudo $user_name

# 更换国内镜像源
cp /etc/apt/sources.list /etc/apt/sources.list.bak
cat << EOF > /etc/apt/sources.list
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ bookworm main contrib non-free non-free-firmware
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ bookworm-updates main contrib non-free non-free-firmware
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ bookworm-backports main contrib non-free non-free-firmware
deb https://mirrors.tuna.tsinghua.edu.cn/debian-security bookworm-security main contrib non-free non-free-firmware
EOF

# 更新系统
apt update && apt upgrade -y
