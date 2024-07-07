#!/bin/bash
# 删除Cockpit外网访问配置
config_file="/etc/cockpit/cockpit.conf"

if [[ -f "$config_file" ]]; then
    if grep -q "Origins" "$config_file"; then
        # 删除Origins参数行
        sed -i '/Origins/d' "$config_file"
        echo "已删除Cockpit外网访问配置。"
    else
        echo "已检查没有配置外网访问参数，跳过操作。"
    fi
else
    echo "已跳过Cockpit外网访问配置。"
fi

# 重启cockpit服务
systemctl try-restart cockpit
