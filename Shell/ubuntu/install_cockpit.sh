#!/bin/bash

# 配置45Drives Repo安装脚本（用于安装Navigator、File Sharing、Identities组件）
curl -sSL https://repo.45drives.com/setup | sudo bash
sudo apt update

# 获取系统版本代号
os_codename=$(awk -F= '/VERSION_CODENAME/{print $2}' /etc/os-release)

# 安装Cockpit及其附属组件（Navigator、File Sharing、Identities组件）
sudo apt install -y -t "$os_codename-backports" cockpit cockpit-pcp
sudo apt install -y cockpit-navigator cockpit-file-sharing cockpit-identities
# 安装Tuned系统调优工具
sudo apt install -y tuned

# 配置首页展示信息
sudo tee /etc/motd > /dev/null <<EOF
我们信任您已经从系统管理员那里了解了日常注意事项。总结起来无外乎这三点：
1、尊重别人的隐私。
2、输入前要先考虑(后果和风险)。
3、权力越大，责任越大。
EOF

# Cockpit调优，设置自动注销闲置及Nginx反向代理Cockpit操作
cockpit_conf="/etc/cockpit/cockpit.conf"
if [[ ! -f "$cockpit_conf" ]]; then
    sudo mkdir -p /etc/cockpit
    sudo tee "$cockpit_conf" > /dev/null <<EOF
[Session]
IdleTimeout=15
Banner=/etc/cockpit/issue.cockpit

[WebService]
ProtocolHeader = X-Forwarded-Proto
ForwardedForHeader = X-Forwarded-For
LoginTo = false
LoginTitle = HomeNAS
EOF
fi

# 检查 /etc/cockpit/issue.cockpit 配置文件是否存在，不存在则创建
issue_file="/etc/cockpit/issue.cockpit"
[[ ! -f "$issue_file" ]] && echo "基于Ubuntu LTS搭建HomeNAS！" | sudo tee "$issue_file" > /dev/null

echo "Cockpit调优配置完成。"

# 重启cockpit服务
sudo systemctl try-restart cockpit
