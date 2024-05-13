#!/bin/bash

# ANSI 转义码颜色定义
green='\033[0;32m'
red='\033[0;31m'
reset='\033[0m'

# 函数：检查服务是否运行并尝试启动服务
check_and_start_service() {
    local service_name=$1
    local service_status=$(systemctl is-active $service_name.service 2>/dev/null)
    if [ "$service_status" != "active" ]; then
        sudo systemctl start $service_name.service >/dev/null 2>&1
        service_status=$(systemctl is-active $service_name.service 2>/dev/null)
    fi
    echo "$service_status"
}

# 函数：检查 Docker 容器是否运行
check_docker_container_running() {
    local container_name=$1
    local running_containers=$(docker ps -q -f "name=$container_name" | wc -l)
    if [ "$running_containers" -gt 0 ]; then
        echo "active"
    else
        echo "inactive"
    fi
}

# 函数：输出服务状态信息
print_service_status() {
    local service_name=$1
    local service_url=$2
    local service_status=$3

    if [ "$service_status" == "active" ]; then
        echo -e "${green}$service_name 服务已运行！${reset}"
        echo -e "请通过浏览器访问 $service_url"
    else
        echo -e "${red}$service_name 服务未能正常运行，请检查。${reset}"
    fi
}

# 获取主机的 IP 地址
host_ip=$(hostname -I | awk '{print $1}')

# Cockpit Web 服务
cockpit_status=$(check_and_start_service cockpit)
print_service_status "Cockpit Web" "https://$host_ip:9090" "$cockpit_status"

# Docker 服务
docker_status=$(systemctl is-active docker.service 2>/dev/null)
if [ "$docker_status" != "active" ]; then
    echo -e "${red}Docker 服务未能正常运行，请检查。${reset}"
fi

# Portainer 服务
if [ "$docker_status" == "active" ]; then
    portainer_status=$(check_docker_container_running "portainer")
    print_service_status "Portainer" "https://$host_ip:9443" "$portainer_status"
fi

# Dockge 服务
if [ "$docker_status" == "active" ]; then
    dockge_status=$(check_docker_container_running "dockge")
    print_service_status "Dockge" "https://$host_ip:5001" "$dockge_status"
fi
