# 设置Cockpit外网访问或删除外网访问配置
read -p "配置外网访问(y) 删除外网访问配置(n)，请输入(y/n): " response
config_file="/etc/cockpit/cockpit.conf"
if [[ -z "$response" || "$response" == "n" ]]; then
    # 用户不做回应或者回答n
    if [[ -f "$config_file" ]]; then
        if grep -q "Origins" "$config_file"; then
            # 删除Origins参数行
            sed -i '/Origins/d' "$config_file"
            echo "已删除对应外网访问参数。"
        else
            echo "检查没有配置外网访问参数，跳过操作。"
        fi
    else
        echo "已跳过Cockpit外网访问配置。"
    fi
else
    # 提示用户输入外网访问域名
    read -p "请输入Cockpit外网访问地址（如有端口号需一并输入）： " domain

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
    echo "已设置Cockpit外网访问域名：https://$domain"
fi
