#!/bin/bash

declare -r CONFIG_FILE="/etc/firewalld/zones/public.xml"

# 读取用户输入
read -p "是否安装防火墙Firewalld? (y/n): " choice

case "$choice" in
    [Yy])
        # 安装 firewalld
        apt update -y && apt install firewalld -y
        ;;
    *)
        echo "跳过安装防火墙Firewalld."
        exit 0
        ;;
esac

# 停止 firewalld 服务
systemctl stop firewalld

# 检查 public.xml 文件是否存在并处理
if [ ! -f "$CONFIG_FILE" ]; then
    # 如果不存在，则创建并添加配置
    tee "$CONFIG_FILE" > /dev/null <<EOF
<?xml version="1.0" encoding="utf-8"?>
<zone>
  <short>Public</short>
  <description>For use in public areas. You do not trust the other computers on networks to not harm your computer. Only selected incoming connections are accepted.</description>
  <service name="ssh"/>
  <service name="dhcpv6-client"/>
  <service name="cockpit"/>
  <forward/>
</zone>
EOF
else
    # 如果存在，则检查是否存在 cockpit 配置项
    if ! grep -q '<service name="cockpit"/>' "$CONFIG_FILE"; then
        # 如果不存在，则添加 cockpit 配置项
        sed -i '/<forward\/>/i \  <service name="cockpit"/>' "$CONFIG_FILE"
    fi
fi

# 启动 firewalld 服务
systemctl start firewalld
