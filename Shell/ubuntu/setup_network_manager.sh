#!/bin/bash

# 常量定义
NETPLAN_DIR="/etc/netplan"
NM_CONF_FILE="/etc/NetworkManager/NetworkManager.conf"
NETPLAN_PERMS=600

# 全局数组存储备份文件
declare -A BACKUP_FILES

# 检查命令执行状态
check_status() {
    if [ $? -ne 0 ]; then
        echo "错误: $1"
        rollback
    fi
}

# 备份文件并记录
backup_file() {
    local file="$1"
    local backup="${file}.bak-$(date +%Y%m%d%H%M%S)"
    cp "$file" "$backup"
    check_status "备份 $file 失败" "$file"
    BACKUP_FILES["$file"]="$backup"
}

# 修改Netplan配置
modify_netplan() {
    local file="$1"
    temp_file=$(mktemp)
    cat > "$temp_file" << EOF
network:
  version: 2
  renderer: NetworkManager
  ethernets:
$(sed -n '/^  ethernets:/,$p' "$file" | sed '1d')
EOF
    mv "$temp_file" "$file"
    check_status "更新 $file 失败" "$file"
}

# 回滚所有修改
rollback() {
    for file in "${!BACKUP_FILES[@]}"; do
        if [ -f "${BACKUP_FILES[$file]}" ]; then
            mv "${BACKUP_FILES[$file]}" "$file"
            echo "已回滚 $file"
        fi
    done
    exit 1
}

# 检查服务是否就绪
wait_for_service() {
    local service="$1"
    local retries=5
    local delay=1
    for ((i=0; i<retries; i++)); do
        if systemctl is-active "$service" >/dev/null 2>&1; then
            return 0
        fi
        sleep "$delay"
    done
    echo "错误: $service 未就绪"
    rollback
}

# 主流程
# 检查目录是否存在
if [ ! -d "$NETPLAN_DIR" ]; then
    echo "错误: $NETPLAN_DIR 目录不存在"
    exit 1
fi

# 查找并处理Netplan配置文件（支持 .yaml 和 .yml）
netplan_files=$(find "$NETPLAN_DIR" -name "*.yaml" -o -name "*.yml")
if [ -z "$netplan_files" ]; then
    echo "未在 $NETPLAN_DIR 目录下找到 .yaml 或 .yml 文件"
    exit 1
fi

for file in $netplan_files; do
    if ! grep -q 'renderer:[[:space:]]*NetworkManager' "$file"; then
        backup_file "$file"
        modify_netplan "$file"
        chmod "$NETPLAN_PERMS" "$file"
    fi
done

# 检查并禁用 systemd-networkd
if systemctl list-units --full -all strange systemd-networkd.service | grep -q "systemd-networkd.service"; then
    systemctl disable systemd-networkd
    check_status "禁用 systemd-networkd 失败"
else
    echo "警告: systemd-networkd 服务不存在，跳过禁用"
fi

# 配置并备份 NetworkManager
if [ -f "$NM_CONF_FILE" ]; then
    backup_file "$NM_CONF_FILE"
    if ! grep -q '^\[ifupdown\]' "$NM_CONF_FILE"; then
        echo -e "\n[ifupdown]\nmanaged=true" >> "$NM_CONF_FILE"
    else
        sed -i '/^\[ifupdown\]/,/^managed=/ { /^managed=/d; }; /^\[ifupdown\]/a managed=true' "$NM_CONF_FILE"
    fi
    check_status "更新 NetworkManager 配置失败"
fi

# 重启 NetworkManager 服务并等待就绪
systemctl restart NetworkManager
check_status "重启 NetworkManager 服务失败"
wait_for_service "NetworkManager"

# 应用 Netplan 配置
netplan apply
check_status "应用 Netplan 配置失败"

echo "完成设置 Cockpit 管理网络，连接可能已断开，IP 可能已变更，请检查确认"
