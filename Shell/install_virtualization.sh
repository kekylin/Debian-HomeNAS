#!/bin/bash

# 获取系统版本代号
os_codename=$(awk -F= '/VERSION_CODENAME/{print $2}' /etc/os-release)

# 安装 cockpit-machines 组件
apt install -y -t "$os_codename-backports" cockpit-machines

# 开启IP包转发功能
echo "开启IP包转发功能..."
sysctl_conf="/etc/sysctl.conf"
if grep -qE "^#?net.ipv4.ip_forward=1" "$sysctl_conf"; then
    sed -i 's/^#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' "$sysctl_conf"
else
    echo "net.ipv4.ip_forward=1" >> "$sysctl_conf"
fi
sysctl -p
echo "已安装虚拟机组件。"

# 重启cockpit服务
systemctl try-restart cockpit
