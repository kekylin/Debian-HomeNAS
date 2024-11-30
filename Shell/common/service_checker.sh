#!/bin/bash

# 定义ANSI颜色代码
declare -A COLORS=(
    [RED]='\033[0;31m'
    [GREEN]='\033[0;32m'
    [YELLOW]='\033[0;33m'
    [BLUE]='\033[0;34m'
    [PURPLE]='\033[0;35m'
    [CYAN]='\033[0;36m'
    [WHITE]='\033[1;37m'
    [RESET]='\033[0m'
)

# 定义日志输出函数
log_message() {
    local msg_type="$1"
    local msg="$2"
    local color="${3:-${COLORS[RESET]}}"  # 默认颜色为重置
    echo -e "${color}[${msg_type}] ${msg}${COLORS[RESET]}"
}

# 检查服务是否活跃
is_service_active() {
    local svc="$1.service"
    if systemctl is-active --quiet "$svc"; then
        return 0
    else
        return 1
    fi
}

# 打印服务状态和访问信息
print_service_status() {
echo -e "${COLORS[CYAN]}--------------------------------------------------${COLORS[RESET]}"
log_message "SUCCESS" "$1 服务已运行！" "${COLORS[GREEN]}"
    log_message "INFO" "请通过浏览器访问 $2" "${COLORS[CYAN]}"
    echo ""  # 添加空行
}

# 检查系统服务模块
check_system_services() {
    local host_ip="$1"
    # 检查cockpit服务
    if is_service_active cockpit; then
        print_service_status "cockpit" "https://${host_ip}:9090"
    fi
}

# 检查Docker容器模块
check_docker_containers() {
    local host_ip="$1"
    declare -A docker_containers=(
        ["ddns-go"]="http://${host_ip}:9876"
        ["dockge"]="http://${host_ip}:5001"
        ["nginx-ui"]="http://${host_ip}:12800"
        ["portainer"]="https://${host_ip}:9443"
        ["portainer_zh-cn"]="http://${host_ip}:9999"
        ["scrutiny"]="http://${host_ip}:9626"
    )

    for container in "${!docker_containers[@]}"; do
        if docker inspect -f '{{.State.Running}}' "$container" 2>/dev/null | grep -q "true"; then
            print_service_status "$container" "${docker_containers[$container]}"
        fi
    done
}

# 检查软件包是否安装
is_package_installed() {
    local pkg="$1"
    dpkg -s "$pkg" >/dev/null 2>&1 && return 0 || return 1
}

# 显示firewalld和fail2ban的提示
display_firewalld_fail2ban_info() {
    local firewalld_installed=$(is_package_installed firewalld && echo "yes" || echo "no")
    local fail2ban_installed=$(is_package_installed fail2ban && echo "yes" || echo "no")

    if [[ "$firewalld_installed" == "yes" ]]; then
        log_message "INFO" "Firewalld防火墙服务已安装，使用时注意放行必要端口。" "${COLORS[CYAN]}"
        echo ""
    fi
    if [[ "$fail2ban_installed" == "yes" ]]; then
        log_message "INFO" "Fail2ban自动封锁服务已安装，5次登陆系统失败，访问者IP将被封禁1小时。" "${COLORS[CYAN]}"
        echo ""
    fi
}

# 主脚本执行部分
host_ip=$(hostname -I | awk '{print $1}')  # 获取主机IP地址

# 检查并显示系统服务状态
check_system_services "$host_ip"

# 检查docker服务是否活跃
if is_service_active docker; then
    check_docker_containers "$host_ip"
fi

# 显示firewalld和fail2ban的提示
display_firewalld_fail2ban_info
