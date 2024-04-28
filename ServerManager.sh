#!/bin/bash

# 获取主机的 IP 地址
host_ip=$(hostname -I | awk '{print $1}')

# 检查 Cockpit Web 服务是否正在运行
cockpit_running=$(systemctl is-active cockpit.service >/dev/null 2>&1 && echo "true" || echo "false")

if [ "$cockpit_running" == "true" ]; then
    echo "Cockpit Web 服务正在运行！"
    echo "请访问 https://$host_ip:9090 来管理服务器。"
else
    echo "Cockpit Web 服务未能正常运行，请检查安装或运行时的问题。"
fi

# 检查 Docker 是否正在运行
docker_running=$(docker info >/dev/null 2>&1 && echo "true" || echo "false")

if [ "$docker_running" == "true" ]; then
    echo "Docker 已经成功运行！"
    echo "请访问 http://$host_ip:9443 来管理 Docker 服务。"
else
    echo "Docker 未能正常运行，请检查安装或运行时的问题。"
fi
