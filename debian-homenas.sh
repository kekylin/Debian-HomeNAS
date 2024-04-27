#!/bin/bash

# 安装必备软件
apt update
apt install -y sudo curl git vim wget gnupg apt-transport-https ca-certificates

# 添加第一个创建的用户至sudo组
first_user=$(awk -F: '$3>=1000 && $1 != "nobody" {print $1}' /etc/passwd | sort | head -n 1)
usermod -aG sudo "$first_user"

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

# Cockpit调优脚本
# 自动注销闲置用户设置
sudo tee -a /etc/cockpit/cockpit.conf > /dev/null <<EOF
[Session]
IdleTimeout=15
Banner=/etc/cockpit/issue.cockpit
EOF
sudo systemctl try-restart cockpit

# 在登录页面添加标题
echo "HomeNAS Based on Debian" | sudo tee /etc/cockpit/issue.cockpit > /dev/null
sudo systemctl try-restart cockpit

# 配置首页展示信息
sudo tee /etc/motd > /dev/null <<EOF
我们信任您已经从系统管理员那里了解了日常注意事项。总结起来无外乎这三点：
1、尊重别人的隐私。
2、输入前要先考虑(后果和风险)。
3、权力越大，责任越大。
EOF

# 设置Cockpit接管网络配置（网络管理工具由network改为NetworkManager）
sudo sed -i 's/^/#/' /etc/network/interfaces

# 安装Tuned系统调优工具
apt install tuned
