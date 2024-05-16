#!/bin/bash

# 备份镜像源配置文件
cp /etc/apt/sources.list /etc/apt/sources.list.bak
# 更换国内镜像源
cat << EOF > /etc/apt/sources.list
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ bookworm main contrib non-free non-free-firmware
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ bookworm-updates main contrib non-free non-free-firmware
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ bookworm-backports main contrib non-free non-free-firmware
deb https://mirrors.tuna.tsinghua.edu.cn/debian-security bookworm-security main contrib non-free non-free-firmware
EOF

# 更新系统
apt update && apt upgrade -y

# 安装必备软件
apt install -y sudo curl git vim wget exim4 gnupg apt-transport-https ca-certificates

# 添加第一个创建的用户（ID：1000）至sudo组
first_user=$(awk -F: '$3>=1000 && $1 != "nobody" {print $1}' /etc/passwd | sort | head -n 1)
usermod -aG sudo "$first_user"
