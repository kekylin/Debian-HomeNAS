#!/bin/bash

# 启用向后移植存储库
echo "deb http://deb.debian.org/debian $(. /etc/os-release && echo $VERSION_CODENAME)-backports main" > /etc/apt/sources.list.d/backports.list
# 配置45Drives Repo安装脚本（用于安装Navigator、File Sharing、Identities组件）
curl -sSL https://repo.45drives.com/setup | bash
apt update

# 安装Cockpit及其附属组件（Navigator、File Sharing、Identities组件）
apt install -y -t $(. /etc/os-release && echo $VERSION_CODENAME)-backports cockpit cockpit-pcp
apt install -y cockpit-navigator cockpit-file-sharing cockpit-identities

# 询问是否安装cockpit-machines
read -p "是否安装虚拟机组件？(y/n): " install_machines

if [[ $install_machines == "y" ]]; then
    # 安装 cockpit-machines 组件
    apt install -y -t $(. /etc/os-release && echo $VERSION_CODENAME)-backports cockpit-machines

    # 开启IP包转发功能
    echo "开启IP包转发功能..."

    # 编辑 /etc/sysctl.conf 文件
    sysctl_conf="/etc/sysctl.conf"
    if grep -qE "^#?net.ipv4.ip_forward=1" "$sysctl_conf"; then
        sed -i 's/^#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' "$sysctl_conf"
    else
        echo "net.ipv4.ip_forward=1" >> "$sysctl_conf"
    fi

    # 应用更改
    sysctl -p

    echo "已安装虚拟机组件。"
else
    echo "已跳过虚拟机组件安装。"
fi

# 配置首页展示信息
tee /etc/motd > /dev/null <<EOF
我们信任您已经从系统管理员那里了解了日常注意事项。总结起来无外乎这三点：
1、尊重别人的隐私。
2、输入前要先考虑(后果和风险)。
3、权力越大，责任越大。
EOF

# 安装Tuned系统调优工具
apt install tuned -y

# cockpit调优，设置自动注销闲置及Nginx反向代理Cockpit操作。
# 检查/etc/cockpit/cockpit.conf配置文件是否存在，不存在则创建
if [ ! -f "/etc/cockpit/cockpit.conf" ]; then
    touch /etc/cockpit/cockpit.conf

    # 插入初始配置内容
    echo "[Session]" > /etc/cockpit/cockpit.conf
    echo "IdleTimeout=15" >> /etc/cockpit/cockpit.conf
    echo "Banner=/etc/cockpit/issue.cockpit" >> /etc/cockpit/cockpit.conf

    echo -e "\n[WebService]" >> /etc/cockpit/cockpit.conf
    echo "ProtocolHeader = X-Forwarded-Proto" >> /etc/cockpit/cockpit.conf
    echo "ForwardedForHeader = X-Forwarded-For" >> /etc/cockpit/cockpit.conf
    echo "LoginTo = false" >> /etc/cockpit/cockpit.conf
    echo "LoginTitle = HomeNAS" >> /etc/cockpit/cockpit.conf
fi

# 检查/etc/cockpit/issue.cockpit配置文件是否存在，不存在则创建
if [ ! -f "/etc/cockpit/issue.cockpit" ]; then
    echo "基于Debian搭建HomeNAS！" > /etc/cockpit/issue.cockpit
fi

# 检查是否需要设置Cockpit外网访问
read -p "是否设置Cockpit外网访问？(y/n): " response
config_file="/etc/cockpit/cockpit.conf"

# Function to delete configuration parameters
delete_params() {
    sed -i '/Origins/d' "$config_file"
    sed -i '/Access-Control-Allow-Origin/d' "$config_file"
    echo "已删除Cockpit外网访问相关配置。"
}

# Function to set configuration parameters
set_params() {
    # 提取当前主机的内网IP地址段
    internal_ip=$(hostname -I | awk '{print $1}')
    internal_subnet=$(echo "$internal_ip" | sed -E 's/\.[0-9]+$/\.0\/24/')

    # 配置Cockpit的Origins和Access-Control-Allow-Origin参数
    if grep -q "Origins" "$config_file"; then
        sed -i "s#^Origins = .*#Origins = https://$domain wss://$domain#" "$config_file"
    else
        sed -i "/\[WebService\]/a Origins = https://$domain wss://$domain" "$config_file"
    fi

    if grep -q "Access-Control-Allow-Origin" "$config_file"; then
        sed -i "s#^Access-Control-Allow-Origin: .*#Access-Control-Allow-Origin: https://$internal_subnet#" "$config_file"
    else
        sed -i "/Origins = /a Access-Control-Allow-Origin: https://$internal_subnet" "$config_file"
    fi
    echo "已设置Cockpit外网访问域名：https://$domain"
    echo "已设置内网访问地址段：https://$internal_subnet"
}

# 判断用户是否选择设置Cockpit外网访问
if [[ -z "$response" || "$response" == "n" ]]; then
    # 用户不做回应或者回答n，删除配置参数
    [[ -f "$config_file" ]] && delete_params
    echo "已跳过Cockpit外网访问配置。"
else
    # 提示用户输入外网访问域名
    read -p "请输入Cockpit外网访问域名和端口号（例如 example.com:9090）： " domain
    # 移除输入中的协议部分
    domain=$(echo "$domain" | sed -E 's#^https?://##')
    # 设置配置参数
    [[ ! -f "$config_file" ]] && echo "[WebService]" > "$config_file"
    set_params
fi

echo "Cockpit调优配置完成。"

# 设置Cockpit接管网络配置（网络管理工具由network改为NetworkManager）
setup_network_configuration() {
    local interfaces_file="/etc/network/interfaces"
    
    if [ -f "$interfaces_file" ]; then
        # 注释掉未注释的行
        sed -i '/^[^#].*/ s/^/#/' "$interfaces_file"
    else
        echo "文件 '$interfaces_file' 不存在，跳过操作。"
    fi
}
# 重启Network Manager服务
restart_network_manager() {
    systemctl restart NetworkManager && echo "已重启 Network Manager 服务。"
}
# 执行主程序
setup_network_configuration
restart_network_manager

# 重启cockpit服务
systemctl try-restart cockpit
