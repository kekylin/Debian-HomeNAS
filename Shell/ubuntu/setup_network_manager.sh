#!/bin/bash

# 确保脚本使用sudo执行
if [[ $EUID -ne 0 ]]; then
    echo "此脚本必须使用sudo权限运行。"
    exit 1
fi

# 查找并确认/etc/netplan目录下存在.yaml配置文件
netplan_file=$(find /etc/netplan/ -name "*.yaml" -print -quit)

if [[ -z "$netplan_file" ]]; then
    echo "未在 /etc/netplan 目录下找到 .yaml 文件。"
    exit 1
fi

# 检查是否已设置 renderer: NetworkManager
if grep -q '^\s*renderer:\s*NetworkManager' "$netplan_file"; then
    echo "已设置NetworkManager管理网络，跳过后续操作。"
    exit 0  # 跳过后面所有操作
fi

# 备份原始文件
cp "$netplan_file" "${netplan_file}.bak" || { echo "备份失败"; exit 1; }

# 修改文件，确保renderer和ethernets缩进对齐并设置权限
awk '/^    ethernets:/ { print "    renderer: NetworkManager" } { print }' "$netplan_file" > "${netplan_file}.tmp" && mv "${netplan_file}.tmp" "$netplan_file"
chmod 600 "$netplan_file" || { echo "设置权限失败"; exit 1; }

# 禁用 systemd-networkd 服务的开机自启
systemctl is-enabled --quiet systemd-networkd && systemctl disable systemd-networkd

echo "已设置NetworkManager管理网络，网络连接3秒后自动断开，IP地址可能已改变，请查询确认。"

# NetworkManager配置文件路径
nm_conf_file="/etc/NetworkManager/NetworkManager.conf"

# 修改NetworkManager配置文件，将managed设置为true
if [[ -f "$nm_conf_file" ]]; then
    if ! grep -q '^\[ifupdown\]' "$nm_conf_file"; then
        echo -e "\n[ifupdown]\nmanaged=true" >> "$nm_conf_file"
    else
        # 更新managed行
        sed -i '/^\[ifupdown\]/,/^\[/ { /^\[ifupdown\]/! { /^managed=/d; } }' "$nm_conf_file"
        echo "managed=true" >> "$nm_conf_file"
    fi
else
    echo "文件 '$nm_conf_file' 不存在，跳过操作。"
fi

# 重启Network Manager服务并检查成功
if systemctl restart NetworkManager; then
    echo "已重启 Network Manager 服务。"
else
    echo "重启 Network Manager 服务失败。"
    exit 1
fi

# 应用netplan配置
sleep 5 # 等待5秒确保网络操作完成
netplan apply || { echo "应用netplan配置失败。"; exit 1; }
