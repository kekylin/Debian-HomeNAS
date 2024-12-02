#!/bin/bash

# 设置Cockpit接管网络配置（网络管理工具由network改为NetworkManager）
interfaces_file="/etc/network/interfaces"
nm_conf_file="/etc/NetworkManager/NetworkManager.conf"

# 注释掉/etc/network/interfaces中的内容
if [[ -f "$interfaces_file" ]]; then
    sed -i '/^[^#]/ s/^/#/' "$interfaces_file"
else
    echo "文件 '$interfaces_file' 不存在，跳过操作。"
fi

# 修改NetworkManager配置文件，将managed设置为true
if [[ -f "$nm_conf_file" ]]; then
    # 如果[ifupdown]部分不存在，添加它
    if ! grep -q '^\[ifupdown\]' "$nm_conf_file"; then
        echo -e "\n[ifupdown]\nmanaged=true" >> "$nm_conf_file"
    else
        # [ifupdown]存在时，替换managed行或追加
        sed -i '/^\[ifupdown\]/,/^\[/ {/^\[ifupdown\]/!{/^managed=/d}}' "$nm_conf_file" # 删除现有的managed行（如果有）
        sed -i '/^\[ifupdown\]/a managed=true' "$nm_conf_file" # 在[ifupdown]下添加managed=true
    fi
else
    echo "文件 '$nm_conf_file' 不存在，跳过操作。"
fi

# 重启Network Manager服务
systemctl restart NetworkManager && echo "已重启 Network Manager 服务。"


# 重启cockpit服务
systemctl try-restart cockpit
