#!/bin/bash

# 创建 debian-homenas 文件夹
mkdir -p debian-homenas

# 定义文件列表和 URL 前缀
files=(
    "system_init.sh"
    "install_cockpit.sh"
    "email_config.sh"
    "system_security.sh"
    "install_docker.sh"
    "install_firewalld.sh"
    "install_fail2ban.sh"
    "service_checker.sh"
)
url_prefix="https://mirror.ghproxy.com/https://raw.githubusercontent.com/kekylin/Debian-HomeNAS/main/"

# 下载所有脚本文件到 debian-homenas 文件夹
for file in "${files[@]}"; do
    wget -O "debian-homenas/$file" -q --show-progress "${url_prefix}${file}" || {
        echo "下载 $file 失败，请检查网络连接或稍后再试。"
        exit 1
    }
done

echo "所有脚本下载完成，开始执行..."

# 依次执行所有下载的脚本
for file in "${files[@]}"; do
    bash "debian-homenas/$file" || {
        echo "执行 $file 失败。"
        exit 1
    }
done

exit 0
