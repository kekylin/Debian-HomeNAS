#!/bin/bash

# 创建 debian-homenas 文件夹
mkdir -p debian-homenas

# 下载所有脚本文件到 debian-homenas 文件夹
wget -O debian-homenas/system_init.sh -q --show-progress https://mirror.ghproxy.com/https://raw.githubusercontent.com/kekylin/Debian-HomeNAS/main/system_init.sh
wget -O debian-homenas/install_cockpit.sh -q --show-progress https://mirror.ghproxy.com/https://raw.githubusercontent.com/kekylin/Debian-HomeNAS/main/install_cockpit.sh
wget -O debian-homenas/email_config.sh -q --show-progress https://mirror.ghproxy.com/https://raw.githubusercontent.com/kekylin/Debian-HomeNAS/main/email_config.sh
wget -O debian-homenas/system_security.sh -q --show-progress https://mirror.ghproxy.com/https://raw.githubusercontent.com/kekylin/Debian-HomeNAS/main/system_security.sh
wget -O debian-homenas/install_docker.sh -q --show-progress https://mirror.ghproxy.com/https://raw.githubusercontent.com/kekylin/Debian-HomeNAS/main/install_docker.sh
wget -O debian-homenas/install_firewalld.sh -q --show-progress https://mirror.ghproxy.com/https://raw.githubusercontent.com/kekylin/Debian-HomeNAS/main/install_firewalld.sh
wget -O debian-homenas/install_fail2ban.sh -q --show-progress https://mirror.ghproxy.com/https://raw.githubusercontent.com/kekylin/Debian-HomeNAS/main/install_fail2ban.sh
wget -O debian-homenas/service_checker.sh -q --show-progress https://mirror.ghproxy.com/https://raw.githubusercontent.com/kekylin/Debian-HomeNAS/main/service_checker.sh

# 确保所有脚本都下载成功
if [ $? -eq 0 ]; then
    echo "所有脚本下载完成，开始执行..."

    # 依次执行所有下载的脚本
    bash debian-homenas/system_init.sh
    bash debian-homenas/install_cockpit.sh
    bash debian-homenas/email_config.sh
    bash debian-homenas/system_security.sh
    bash debian-homenas/install_docker.sh
    bash debian-homenas/install_firewalld.sh
    bash debian-homenas/install_fail2ban.sh
    bash debian-homenas/service_checker.sh
else
    echo "下载脚本失败，请检查网络连接或稍后再试。"
    exit 1
fi

exit 0
