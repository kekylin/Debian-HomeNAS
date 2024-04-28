#!/bin/bash

# 下载所有脚本文件
wget -O systemsetup.sh -q --show-progress https://mirror.ghproxy.com/https://raw.githubusercontent.com/kekylin/debian-homenas/main/systemsetup.sh
wget -O install_cockpit.sh -q --show-progress https://mirror.ghproxy.com/https://raw.githubusercontent.com/kekylin/debian-homenas/main/install_cockpit.sh
wget -O systemsec.sh -q --show-progress https://mirror.ghproxy.com/https://raw.githubusercontent.com/kekylin/debian-homenas/main/systemsec.sh
wget -O dockersetup.sh -q --show-progress https://mirror.ghproxy.com/https://raw.githubusercontent.com/kekylin/debian-homenas/main/dockersetup.sh
wget -O servermanager.sh -q --show-progress https://mirror.ghproxy.com/https://raw.githubusercontent.com/kekylin/Debian-HomeNAS/main/servermanager.sh

# 确保所有脚本都下载成功
if [ $? -eq 0 ]; then
    echo "所有脚本下载完成，开始执行..."
    
    # 依次执行所有下载的脚本
    bash systemsetup.sh
    bash install_cockpit.sh
    bash systemsec.sh
    bash dockersetup.sh
    bash servermanager.sh
else
    echo "下载脚本失败，请检查网络连接或稍后再试。"
    exit 1
fi

exit 0
