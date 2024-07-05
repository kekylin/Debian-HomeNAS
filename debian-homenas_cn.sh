#!/bin/bash

# 常量定义
DEBIAN_HOMENAS_DIR="debian-homenas"
URL_PREFIX="https://gitee.com/kekylin/Debian-HomeNAS/raw/test/Shell/"
COLOR_RED="31"
COLOR_GREEN="32"
COLOR_BLUE="34"

# 脚本文件列表
SCRIPT_URLS=(
    "system_init.sh"             # 0  系统初始配置
    "install_cockpit.sh"         # 1  安装面板Cockpit
    "install_virtualization.sh"  # 2  安装虚拟机组件
    "setup_cockpit_access.sh"    # 3  外网访问Cockpit
    "email_config.sh"            # 4  邮件通知服务
    "system_security.sh"         # 5  配置基础安全防护
    "install_firewalld.sh"       # 6  安装防火墙服务
    "install_fail2ban.sh"        # 7  安装自动封锁服务
    "install_docker.sh"          # 8  安装Docker
    "dockerhub_mirror.sh"        # 9  添加镜像地址
    "deploy-containers.sh"       # 10 安装容器管理
    "docker_backup_restore.sh"   # 11 备份与恢复
    "service_checker.sh"         # 12 安装服务查询
)

# 创建目录
[[ ! -d "$DEBIAN_HOMENAS_DIR" ]] && mkdir -p "$DEBIAN_HOMENAS_DIR"

# 函数：打印带颜色的输出
color_print() {
    local color="$1"
    shift
    echo -e "\033[${color}m$*\033[0m"
}

# 函数：下载并执行脚本
execute_script() {
    local index="$1"
    local alias="$2"
    wget -q --show-progress -O "${DEBIAN_HOMENAS_DIR}/${SCRIPT_URLS[$index]}" "${URL_PREFIX}${SCRIPT_URLS[$index]}" || {
        color_print $COLOR_RED "下载 ${SCRIPT_URLS[$index]} 失败，请检查网络连接或稍后再试。"
        return 1
    }
    color_print $COLOR_BLUE "=================================================="
    color_print $COLOR_BLUE "正在执行 ${alias}..."
    color_print $COLOR_BLUE "=================================================="
    if bash "${DEBIAN_HOMENAS_DIR}/${SCRIPT_URLS[$index]}"; then
        color_print $COLOR_GREEN "${alias} 执行完成。"
    else
        color_print $COLOR_RED "${alias} 执行失败。"
    fi
}

# 函数：显示菜单
show_menu() {
    color_print $COLOR_BLUE "=================================================="
    echo -e "$1"
    color_print $COLOR_BLUE "=================================================="
    echo -n -e "\033[${COLOR_BLUE}m请输入选择：\033[0m"
}

# 函数：显示欢迎信息
show_welcome() {
    color_print $COLOR_BLUE "=================================================="
    echo -e "                 Debian HomeNAS\n\n                                  QQ群：339169752\n作者：kekylin\n项目：https://github.com/kekylin/Debian-HomeNAS"
    if [ "$first_run" = true ]; then
        color_print $COLOR_GREEN "--------------------------------------------------\n温馨提示！\n1、系统安装后首次运行，建议选择执行全部脚本。\n2、安装防火墙后重启一次系统再使用。\n3、多选空格分隔，例如：1 3 5"
    fi
}

# 函数：主菜单处理
handle_main_menu() {
    first_run=true
    if [ "$first_run" = true ]; then
        clear
    fi
    while true; do
        show_welcome
        show_menu "$main_menu"
        read -r choice
        case "$choice" in
            99)
                for index in ${menu_actions["99"]}; do
                    execute_script "$index" "${menu_lines[$((index + 1))]}"
                done
                ;;
            1|3|6)
                execute_script "${menu_actions[$choice]}" "${menu_lines[$choice]}"
                ;;
            2|4|5)
                handle_submenu "$choice"
                ;;
            0)
                color_print $COLOR_BLUE "退出脚本。"
                exit 0
                ;;
            *)
                color_print $COLOR_RED "\n无效选择：$choice。请重新输入。\n"
                ;;
        esac
        first_run=false
    done
}

# 函数：子菜单处理
handle_submenu() {
    local submenu_choice="$1"
    local submenu="submenu_$submenu_choice"
    local actions=(${submenu_actions[$submenu]})
    local submenu_lines=($(echo "${submenus[$submenu]}" | tail -n +3 | head -n -2 | awk '{print $2}'))

    while true; do
        show_menu "${submenus[$submenu]}"
        read -r sub_choice
        case "$sub_choice" in
            0)
                break
                ;;
            *)
                if [[ $sub_choice =~ ^[1-4]$ ]] && [ "$sub_choice" -le "${#actions[@]}" ]; then
                    execute_script "${actions[$((sub_choice - 1))]}" "${submenu_lines[$((sub_choice - 1))]}"
                else
                    color_print $COLOR_RED "\n无效选择：$sub_choice。请重新输入。\n"
                fi
                ;;
        esac
    done
}

# 主菜单定义
main_menu=$(cat <<-EOF
1、系统初始配置
2、系统管理面板
3、邮件通知服务
4、系统安全防护
5、Docker服务
6、安装服务查询
99、一键配置HomeNAS
0、退出脚本
EOF
)

# 子菜单定义
submenu_2=$(cat <<-EOF
系统管理面板
--------------------------------------------------
1、安装面板Cockpit
2、安装虚拟机组件
3、外网访问Cockpit
0、返回
EOF
)

submenu_4=$(cat <<-EOF
系统安全防护
--------------------------------------------------
1、配置基础安全防护
2、安装防火墙服务
3、安装自动封锁服务
0、返回
EOF
)

submenu_5=$(cat <<-EOF
Docker服务
--------------------------------------------------
1、安装Docker
2、添加镜像地址
3、安装容器管理
4、备份与恢复
0、返回
EOF
)

# 菜单项及其对应的脚本索引
declare -A menu_actions=(
    [99]="0 1 2 3 4 5 6 7 8 9 10 12" # 一键配置HomeNAS（排除备份与恢复）
    [1]="0"
    [2]="submenu_2"
    [3]="4"
    [4]="submenu_4"
    [5]="submenu_5"
    [6]="12"
)

# 菜单项及其显示名称
declare -A menu_lines=(
    [1]="系统初始配置"
    [2]="系统管理面板"
    [3]="邮件通知服务"
    [4]="系统安全防护"
    [5]="Docker服务"
    [6]="安装服务查询"
    [99]="一键配置HomeNAS"
)

declare -A submenus=(
    [submenu_2]="$submenu_2"
    [submenu_4]="$submenu_4"
    [submenu_5]="$submenu_5"
)

# 子菜单对应的脚本索引
declare -A submenu_actions=(
    [submenu_2]="1 2 3"
    [submenu_4]="5 6 7"
    [submenu_5]="8 9 10 11"
)

# 启动脚本并显示欢迎信息和温馨提示信息
handle_main_menu
