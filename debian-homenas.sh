#!/bin/bash

# 常量定义
DEBIAN_HOMENAS_DIR="debian-homenas"
URL_PREFIX="https://raw.githubusercontent.com/kekylin/Debian-HomeNAS/main/Shell/"
SCRIPT_URLS=(
    "system_init.sh"
    "install_cockpit.sh"
    "email_config.sh"
    "system_security.sh"
    "install_docker.sh"
    "install_firewalld.sh"
    "install_fail2ban.sh"
    "service_checker.sh"
)
SCRIPT_ALIASES=(
    "系统初始化"
    "安装系统管理面板"
    "配置邮件发送服务"
    "配置系统安全防护"
    "安装Docker服务"
    "安装防火墙服务"
    "安装自动封锁服务"
    "服务运行状态提示"
)
declare -A COLORS=(
    [BLUE]="\033[34m"
    [MAGENTA]="\033[35m"
    [GREEN]="\033[32m"
    [RED]="\033[31m"
    [RESET]="\033[0m"
)

# 函数：打印带颜色的输出
color_print() {
    local color="$1"
    shift
    echo -e "${COLORS[$color]}$*${COLORS[RESET]}"
}

# 函数：下载文件并检查下载是否成功
download_file() {
    local file="$1"
    wget -q --show-progress -O "${DEBIAN_HOMENAS_DIR}/${file}" "${URL_PREFIX}${file}" || {
        color_print RED "下载 ${file} 失败，请检查网络连接或稍后再试。"
        exit 1
    }
}

# 函数：下载所有脚本
download_all_scripts() {
    mkdir -p "$DEBIAN_HOMENAS_DIR"
    for file in "${SCRIPT_URLS[@]}"; do
        download_file "${file}"
    done
}

# 函数：执行一个脚本
execute_script() {
    local script="$1"
    local alias="$2"
    if [ ! -f "${DEBIAN_HOMENAS_DIR}/${script}" ]; then
        download_file "${script}"
    fi
    color_print BLUE "=================================================="
    color_print BLUE "正在执行 ${alias}..."
    color_print BLUE "=================================================="
    bash "${DEBIAN_HOMENAS_DIR}/${script}"
    local exit_code=$?
    if [ $exit_code -eq 0 ]; then
        color_print GREEN "${alias} 执行完成。"
    else
        color_print RED "${alias} 执行失败。"
    fi
    return $exit_code
}

# 函数：显示菜单
show_menu() {
    color_print BLUE "=================================================="
    if [ "$first_run" = true ]; then
        color_print BLUE "温馨提示！\n1、系统安装后首次运行，请选择执行全部脚本。\n2、多选空格分隔，例如：1 3 5\n--------------------------------------------------"
    fi
    for ((i = 0; i < ${#SCRIPT_ALIASES[@]}; i++)); do
        color_print MAGENTA "$((i + 1)). ${SCRIPT_ALIASES[i]}"
    done
    color_print MAGENTA "9. 执行全部脚本"
    color_print MAGENTA "0. 退出"
    color_print BLUE "=================================================="
    echo -n -e "${COLORS[BLUE]}请输入脚本编号：${COLORS[RESET]}"
}

# 清屏并显示欢迎信息
clear
color_print BLUE "=================================================="
echo -e "                 Debian HomeNAS\n\n                                  QQ群：339169752\n作者：kekylin\n项目：https://github.com/kekylin/Debian-HomeNAS"

# 主程序循环
first_run=true
while true; do
    show_menu
    read -r -a choices

    if [ ${#choices[@]} -eq 0 ]; then
        color_print RED "\n未选择任何脚本，请重新输入。\n"
        continue
    fi

    for choice in "${choices[@]}"; do
        case "$choice" in
            [1-8])
                index=$((choice - 1))
                script="${SCRIPT_URLS[index]}"
                alias="${SCRIPT_ALIASES[index]}"
                execute_script "${script}" "${alias}"
                ;;
            9)
                download_all_scripts
                color_print BLUE "=================================================="
                color_print BLUE "所有脚本下载完成。"
                color_print BLUE "=================================================="
                for ((i = 0; i < ${#SCRIPT_URLS[@]}; i++)); do
                    execute_script "${SCRIPT_URLS[i]}" "${SCRIPT_ALIASES[i]}"
                done
                ;;
            0)
                color_print BLUE "退出脚本。"
                exit 0
                ;;
            *)
                color_print RED "\n无效选择：$choice。请重新输入。\n"
                continue 2
                ;;
        esac
    done

    read -n 1 -s -r -p "按任意键继续..."
    echo -e "\n=================================================="

    # 将首次运行标志设为 false，确保之后不再显示首次运行的提示
    first_run=false
done
