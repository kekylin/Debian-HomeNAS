#!/bin/bash

# 常量定义
DEBIAN_HOMENAS_DIR="debian-homenas"
URL_PREFIX="https://raw.githubusercontent.com/kekylin/Debian-HomeNAS/main/Shell/"
SCRIPT_URLS=(
    "system_init.sh"
    "install_cockpit.sh"
    "email_config.sh"
    "system_security.sh"
    "install_firewalld.sh"
    "install_fail2ban.sh"
    "install_docker.sh"
    "deploy-containers.sh"
    "service_checker.sh"
)
SCRIPT_ALIASES=(
    "系统初始化"
    "安装系统管理面板"
    "配置邮件发送服务"
    "配置系统安全防护"
    "安装防火墙服务"
    "安装自动封锁服务"
    "安装Docker服务"
    "安装容器应用服务"
    "服务运行状态提示"
)

# 检查是否存在 debian-homenas 目录，不存在则创建
[ ! -d "$DEBIAN_HOMENAS_DIR" ] && mkdir -p "$DEBIAN_HOMENAS_DIR"

# 函数：打印带颜色的输出
color_print() {
    local color="$1"
    shift
    echo -e "\033[${color}m$*\033[0m"
}

# 函数：下载并执行脚本
execute_script() {
    local script="$1"
    local alias="$2"
    wget -q --show-progress -O "${DEBIAN_HOMENAS_DIR}/${script}" "${URL_PREFIX}${script}" || {
        color_print 31 "下载 ${script} 失败，请检查网络连接或稍后再试。"
        exit 1
    }
    color_print 34 "=================================================="
    color_print 34 "正在执行 ${alias}..."
    color_print 34 "=================================================="
    bash "${DEBIAN_HOMENAS_DIR}/${script}"
    if [ $? -eq 0 ]; then
        color_print 32 "${alias} 执行完成。"
    else
        color_print 31 "${alias} 执行失败。"
    fi
}

# 函数：显示菜单
show_menu() {
    color_print 34 "=================================================="
    if [ "$first_run" = true ]; then
        color_print 34 "温馨提示！\n1、系统安装后首次运行，请选择执行全部脚本。\n2、如选择安装防火墙，请在安装完成后重启系统再正式使用。\n3、多选空格分隔，例如：1 3 5\n--------------------------------------------------"
    fi
    for ((i = 0; i < ${#SCRIPT_ALIASES[@]}; i++)); do
        color_print 35 "$((i + 1)). ${SCRIPT_ALIASES[i]}"
    done
    color_print 35 "99. 执行全部脚本"
    color_print 35 "0. 退出"
    color_print 34 "=================================================="
    echo -n -e "\033[34m请输入脚本编号：\033[0m"
}

# 清屏并显示欢迎信息
clear
color_print 34 "=================================================="
echo -e "                 Debian HomeNAS\n\n                                  QQ群：339169752\n作者：kekylin\n项目：https://github.com/kekylin/Debian-HomeNAS"

# 主程序循环
first_run=true
while true; do
    show_menu
    read -r -a choices

    if [ ${#choices[@]} -eq 0 ]; then
        color_print 31 "\n未选择任何脚本，请重新输入。\n"
        continue
    fi

    for choice in "${choices[@]}"; do
        case "$choice" in
            [1-9])
                index=$((choice - 1))
                execute_script "${SCRIPT_URLS[index]}" "${SCRIPT_ALIASES[index]}"
                ;;
            99)
                for ((i = 0; i < ${#SCRIPT_URLS[@]}; i++)); do
                    execute_script "${SCRIPT_URLS[i]}" "${SCRIPT_ALIASES[i]}"
                done
                ;;
            0)
                color_print 34 "退出脚本。"
                exit 0
                ;;
            *)
                color_print 31 "\n无效选择：$choice。请重新输入。\n"
                continue 2
                ;;
        esac
    done

    read -n 1 -s -r -p "按任意键继续..."
    echo -e "\n=================================================="

    # 将首次运行标志设为 false，确保之后不再显示首次运行的提示
    first_run=false
done
