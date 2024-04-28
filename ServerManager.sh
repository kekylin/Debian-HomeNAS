#!/bin/bash

# 获取主机的 IP 地址
host_ip=$(hostname -I | awk '{print $1}')

# 检查 Cockpit Web 服务是否正在运行
cockpit_running=$(systemctl is-active cockpit.service >/dev/null 2>&1 && echo "true" || echo "false")

if [ "$cockpit_running" == "true" ]; then
    echo "Cockpit Web 服务正在运行！"
    echo "请访问 https://$host_ip:9090"
else
    echo "Cockpit Web 服务未能正常运行，请检查。"
fi

# 检查 Docker 服务是否正在运行
docker_running=$(systemctl is-active docker.service >/dev/null 2>&1 && echo "true" || echo "false")

# 检查 Portainer 服务是否正在运行
portainer_running=$(docker ps -q -f "name=portainer" | wc -l)

if [ "$docker_running" == "true" ] && [ "$portainer_running" -gt 0 ]; then
    echo "Docker Portainer 服务正在运行！"
    echo "请访问 https://$host_ip:9443"
elif [ "$docker_running" == "false" ]; then
    echo "Docker 服务未能正常运行，请检查。"
elif [ "$portainer_running" -eq 0 ]; then
    echo "Portainer 服务未能正常运行，请检查。"
fi
