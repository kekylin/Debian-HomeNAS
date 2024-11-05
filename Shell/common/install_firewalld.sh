#!/bin/bash

declare -r CONFIG_FILE="/etc/firewalld/zones/public.xml"

# 1. 禁用 UFW 防火墙（如果存在）
if command -v ufw &> /dev/null; then
    echo "检测到 UFW 防火墙，正在停止并禁用..."
    systemctl stop ufw
    systemctl disable ufw
    echo "UFW 防火墙已停止并禁止开机自启。"
fi

# 2. 安装 firewalld
echo "安装 firewalld 防火墙..."
apt update && apt install firewalld -y

# 3. 停止 firewalld 服务（但不禁用开机自启）
echo "安装完成，停止 firewalld 服务..."
systemctl stop firewalld

# 4. 配置 firewalld 防火墙规则
if [ ! -f "$CONFIG_FILE" ]; then
    echo "配置 firewalld 防火墙规则..."
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
    # 如果文件已存在，检查并添加 cockpit 配置
    if ! grep -q '<service name="cockpit"/>' "$CONFIG_FILE"; then
        echo "添加 cockpit 服务配置..."
        sed -i '/<forward\/>/i \  <service name="cockpit"/>' "$CONFIG_FILE"
    fi
fi

echo "防火墙安装完成。"
