#!/bin/bash

# 配置45Drives Repo安装脚本（用于安装Navigator、File Sharing、Identities组件）
curl -sSL https://repo.45drives.com/setup | bash
apt update

# 获取系统版本代号
os_codename=$(awk -F= '/VERSION_CODENAME/{print $2}' /etc/os-release)

# 安装Cockpit及其附属组件（Navigator、File Sharing、Identities组件）
apt install -y -t "$os_codename-backports" cockpit cockpit-pcp
apt install -y cockpit-navigator cockpit-file-sharing cockpit-identities

# 配置首页展示信息
cat <<EOF > /etc/motd
我们信任您已经从系统管理员那里了解了日常注意事项。总结起来无外乎这三点：
1、尊重别人的隐私。
2、输入前要先考虑(后果和风险)。
3、权力越大，责任越大。
EOF

# 安装Tuned系统调优工具
apt install -y tuned

# Cockpit调优，设置自动注销闲置及Nginx反向代理Cockpit操作
cockpit_conf="/etc/cockpit/cockpit.conf"
if [[ ! -f "$cockpit_conf" ]]; then
    mkdir -p /etc/cockpit
    cat <<EOF > "$cockpit_conf"
[Session]
IdleTimeout=15
Banner=/etc/cockpit/issue.cockpit

[WebService]
ProtocolHeader = X-Forwarded-Proto
ForwardedForHeader = X-Forwarded-For
LoginTo = false
LoginTitle = HomeNAS
EOF
fi

# 检查 /etc/cockpit/issue.cockpit 配置文件是否存在，不存在则创建
issue_file="/etc/cockpit/issue.cockpit"
[[ ! -f "$issue_file" ]] && echo "基于Debian搭建HomeNAS！" > "$issue_file"

echo "Cockpit调优配置完成。"


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
