#!/bin/bash

# ANSI 转义码颜色定义
readonly GREEN='\033[0;32m'
readonly RESET='\033[0m'

# 函数：检查服务是否运行并尝试启动服务
check_and_start_service() {
    local service_name=$1
    local service_status
    service_status=$(systemctl is-active "$service_name.service" 2>/dev/null)
    if [[ $service_status != "active" ]]; then
        systemctl start "$service_name.service" >/dev/null 2>&1
        service_status=$(systemctl is-active "$service_name.service" 2>/dev/null)
    fi
    echo "$service_status"
}

# 函数：检查 Docker 容器是否运行
check_docker_container_running() {
    local container_name=$1
    if docker ps -q -f "name=$container_name" | grep -q .; then
        echo "active"
    else
        echo "inactive"
    fi
}

# 函数：输出服务状态信息
print_service_status() {
    local service_name=$1
    local service_url=$2
    echo -e "${GREEN}$service_name 服务已运行！${RESET}"
    echo -e "请通过浏览器访问 $service_url"
}

# 获取主机的 IP 地址
host_ip=$(hostname -I | awk '{print $1}')

# Cockpit Web 服务
if [[ $(check_and_start_service cockpit) == "active" ]]; then
    print_service_status "Cockpit Web" "https://$host_ip:9090"
fi

# Docker 服务
if [[ $(check_and_start_service docker) == "active" ]]; then
    # 获取本机IP地址
    host_ip=$(hostname -I | awk '{print $1}')

    # 定义要检查的Docker容器名称及其访问地址
    declare -A docker_containers=(
        ["ddns-go"]="http://$host_ip:9876"
        ["dockge"]="http://$host_ip:5001"
        ["nginx-ui"]="http://$host_ip:12800"
        ["portainer"]="https://$host_ip:9443"
        ["portainer_zh-cn"]="http://$host_ip:9999"
        ["scrutiny"]="http://$host_ip:9626"
    )
    
    for container_name in "${!docker_containers[@]}"; do
        if [[ $(check_docker_container_running "$container_name") == "active" ]]; then
            print_service_status "$container_name" "${docker_containers[$container_name]}"
        fi
    done
fi
