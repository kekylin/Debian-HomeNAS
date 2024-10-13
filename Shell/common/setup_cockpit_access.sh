#!/bin/bash
# 设置Cockpit外网访问

read -p "Cockpit外网访问地址，如有端口号需一并输入。
【例如： baidu.com 或 baidu.com:9090 】
请输入： " domain

config_file="/etc/cockpit/cockpit.conf"

# 移除输入中的协议部分
domain=$(echo "$domain" | sed -E 's#^https?://##')

# 提取当前主机内网IP地址
internal_ip=$(hostname -I | awk '{print $1}')

# 配置Cockpit的Origins参数
if [[ -f "$config_file" ]]; then
    if grep -q "Origins" "$config_file"; then
        sed -i "s#^Origins = .*#Origins = https://$domain wss://$domain https://$internal_ip:9090#" "$config_file"
    else
        sed -i "/\[WebService\]/a Origins = https://$domain wss://$domain https://$internal_ip:9090" "$config_file"
    fi
else
    echo "[WebService]" > "$config_file"
    echo "Origins = https://$domain wss://$domain https://$internal_ip:9090" >> "$config_file"
fi

echo "已设置Cockpit外网访问地址：https://$domain"

# 重启cockpit服务
systemctl try-restart cockpit
