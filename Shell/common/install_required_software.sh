#!/bin/bash

# 检查是否有sudo命令
SUDO=""
if command -v sudo > /dev/null; then
    SUDO="sudo"
fi

# 更新软件源
$SUDO apt update

# 安装必备软件
$SUDO apt install -y sudo curl git vim wget exim4 gnupg apt-transport-https ca-certificates smartmontools

# 添加第一个创建的用户（ID：1000）至sudo组
first_user=$(awk -F: '$3>=1000 && $1 != "nobody" {print $1}' /etc/passwd | sort | head -n 1)

# 使用sudo（如果可用）添加用户到sudo组
if [ -n "$SUDO" ]; then
    $SUDO usermod -aG sudo "$first_user"
else
    usermod -aG sudo "$first_user"  # 需要以root身份运行，确保有足够权限
fi
