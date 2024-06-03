#!/bin/bash

# 创建 debian-homenas 文件夹
mkdir -p debian-homenas

# 定义文件列表、别名和 URL 前缀
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
aliases=(
    "系统初始化"
    "安装Cockpit面板及调优"
    "安装邮件收发服务"
    "配置系统安全防护"
    "安装Docker服务"
    "安装防火墙服务"
    "安装自动封锁服务"
    "服务检查及信息提示"
)
url_prefix="https://mirror.ghproxy.com/https://raw.githubusercontent.com/kekylin/Debian-HomeNAS/main/"

# 下载所有脚本文件到 debian-homenas 文件夹
for i in "${!files[@]}"; do
    wget -O "debian-homenas/${files[i]}" -q --show-progress "${url_prefix}${files[i]}" || {
        echo "下载 ${files[i]} 失败，请检查网络连接或稍后再试。"
        exit 1
    }
done

echo "所有脚本下载完成。"

# 显示菜单并让用户选择要执行的脚本
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo -e "${GREEN}首次运行请选“全部执行”（多选空格分隔，例如：1 3 5）：${NC}"
for i in "${!aliases[@]}"; do
    printf "%d) %s\n" $((i+1)) "${aliases[i]}"
done
echo "9) 全部执行"
echo "0) 退出"

# 读取用户输入
read -p "请输入选择的脚本编号： " -a choices

# 执行选择的脚本
for choice in "${choices[@]}"; do
    if [[ "$choice" =~ ^[1-8]$ ]]; then
        script="${files[$((choice-1))]}"
        echo "正在执行 ${aliases[$((choice-1))]}..."
        bash "debian-homenas/$script" || {
            echo "执行 ${aliases[$((choice-1))]} 失败。"
            exit 1
        }
    elif [ "$choice" -eq 9 ]; then
        echo "正在执行所有脚本..."
        for i in "${!files[@]}"; do
            echo "正在执行 ${aliases[i]}..."
            bash "debian-homenas/${files[i]}" || {
                echo "执行 ${aliases[i]} 失败。"
                exit 1
            }
        done
        break
    elif [ "$choice" -eq 0 ]; then
        echo "退出脚本。"
        exit 0
    else
        echo "无效选择：$choice。"
    fi
done

exit 0
