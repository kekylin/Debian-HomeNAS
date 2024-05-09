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
    to_install+=("cockpit-machines")
fi
# 根据用户回答安装组件
for component in "${to_install[@]}"; do
    apt install -y -t $(. /etc/os-release && echo $VERSION_CODENAME)-backports "$component"
done

# 在登录页面添加标题
echo "HomeNAS Based on Debian" | sudo tee /etc/cockpit/issue.cockpit > /dev/null

# 配置首页展示信息
sudo tee /etc/motd > /dev/null <<EOF
我们信任您已经从系统管理员那里了解了日常注意事项。总结起来无外乎这三点：
1、尊重别人的隐私。
2、输入前要先考虑(后果和风险)。
3、权力越大，责任越大。
EOF

# 安装Tuned系统调优工具
apt install tuned -y

# cockpit调优，设置自动注销闲置的用户操作，设置接管网络操作。
# 检查配置文件中是否已经包含相同的内容
check_config() {
    local config_file="$1"
    local config_content="$2"

    if [ -f "$config_file" ] && grep -qFx "$config_content" "$config_file"; then
        echo "配置文件 '$config_file' 已经包含相同的配置，跳过操作。"
        return 0
    else
        return 1
    fi
}

# 设置Cockpit调优配置
setup_cockpit_conf() {
    local cockpit_conf_file="/etc/cockpit/cockpit.conf"
    local cockpit_conf_content="[Session]
IdleTimeout=15
Banner=/etc/cockpit/issue.cockpit"

    if ! check_config "$cockpit_conf_file" "$cockpit_conf_content"; then
        sudo mkdir -p "$(dirname "$cockpit_conf_file")"
        echo "" | sudo tee -a "$cockpit_conf_file" > /dev/null
        echo "$cockpit_conf_content" | sudo tee -a "$cockpit_conf_file" > /dev/null
        echo "已将配置写入到 '$cockpit_conf_file' 文件中。"
    fi
}

# 检查并注释配置文件中未注释的行
comment_uncommented_lines() {
    local file="$1"
    local commented_file="${file}.commented"

    # 将未注释的行添加注释符号并写入到新文件
    sed 's/^[^#]/#&/' "$file" > "$commented_file"

    # 检查是否有未注释的行，如果有，则替换原文件
    if ! cmp -s "$file" "$commented_file"; then
        sudo mv "$commented_file" "$file"
        echo "已将配置注释写入到 '$file' 文件中。"
    else
        echo "文件 '$file' 中所有内容已经被注释，跳过操作。"
        rm "$commented_file"
    fi
}

# 设置Cockpit接管网络配置（网络管理工具由network改为NetworkManager）
setup_network_configuration() {
    local interfaces_file="/etc/network/interfaces"
    
    if [ -f "$interfaces_file" ]; then
        comment_uncommented_lines "$interfaces_file"
    else
        echo "文件 '$interfaces_file' 不存在，跳过操作。"
    fi
}

# 重启Network Manager服务
restart_network_manager() {
    sudo systemctl restart NetworkManager
    echo "已重启 Network Manager 服务。"
}

# 执行主程序
setup_cockpit_conf
setup_network_configuration
restart_network_manager

# 重启cockpit服务
sudo systemctl try-restart cockpit
