#!/bin/bash

# 1. 确保脚本以 root 或 sudo 用户执行
if [[ $EUID -ne 0 ]] && ! groups $USER | grep -q "\bsudo\b"; then
    echo "此脚本必须以 root 用户或 sudo 权限运行。"
    exit 1
fi

# 常量定义
DEBIAN_HOMENAS_DIR="debian-homenas"
URL_PREFIX="https://gitee.com/kekylin/Debian-HomeNAS/raw/main/Shell"
COLOR_RED="31"
COLOR_GREEN="32"
COLOR_BLUE="34"

# 定义脚本组（按目录分类）
declare -A SCRIPT_GROUPS=(
    [common]="
        cancel_login_notify.sh        # c1  取消用户登录通知
        deploy-containers.sh          # c2  安装容器应用
        docker_backup_restore.sh      # c3  备份与恢复
        dockerhub_mirror.sh           # c4  添加镜像地址
        email_config.sh               # c5  设置发送邮件账户
        install_fail2ban.sh           # c6  安装自动封锁服务
        install_firewalld.sh          # c7  安装防火墙服务
        install_virtualization.sh     # c8  安装虚拟机组件
        login_notify.sh               # c9  用户登录发送通知
        remove_cockpit_access.sh      # c10 删除外网访问配置
        service_checker.sh            # c11 安装服务查询
        setup_cockpit_access.sh       # c12 外网访问Cockpit
        system_security.sh            # c13 配置基础安全防护
    "
    [debian]="
        install_cockpit.sh            # d1  安装面板Cockpit
        install_docker.sh             # d2  安装Docker
        system_init.sh                # d3  系统初始配置
    "
    [ubuntu]="
        install_cockpit.sh            # u1  安装面板Cockpit
        install_docker.sh             # u2  安装Docker
        setup_network_manager.sh      # u3  设置NetworkManager管理网络
        system_init.sh                # u4  系统初始配置
    "
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
    local group="$1"
    local script="$2"
    local alias="$3"
    local script_url="${URL_PREFIX}/${group}/${script}"
    
    wget -q --show-progress -O "${DEBIAN_HOMENAS_DIR}/${script}" "${script_url}" || {
        color_print $COLOR_RED "下载 ${script} 失败，请检查网络连接或稍后再试。"
        return 1
    }
    
    color_print $COLOR_BLUE "=================================================="
    color_print $COLOR_BLUE "正在执行 ${alias}..."
    color_print $COLOR_BLUE "=================================================="
    
    if bash "${DEBIAN_HOMENAS_DIR}/${script}"; then
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
        color_print $COLOR_GREEN "--------------------------------------------------\n温馨提示！\n1、系统安装后首次运行，建议执行“一键配置HomeNAS”。\n2、安装防火墙后重启一次系统再使用。\n3、菜单选项支持多选，空格分隔（如：1 3 5）。"
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
        read -r -a choices
        for choice in "${choices[@]}"; do
            case "$choice" in
                99)
                    for group in "${!SCRIPT_GROUPS[@]}"; do
                        for script in ${SCRIPT_GROUPS[$group]}; do
                            execute_script "$group" "$script" "$script"
                        done
                    done
                    ;;
                1|6)
                    execute_script "common" "${menu_actions[$choice]}" "${menu_lines[${menu_actions[$choice]}]}"
                    ;;
                2|3|4|5)
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
        done
        first_run=false
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
4、删除外网访问配置
0、返回
EOF
)

submenu_3=$(cat <<-EOF
邮件通知服务
--------------------------------------------------
1、设置发送邮件账户
2、用户登录发送通知
3、取消用户登录通知
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
3、安装容器应用
4、备份与恢复
0、返回
EOF
)

# 菜单项及其对应的脚本索引
declare -A menu_actions=(
    [99]="0 1 5 6 8 9 10 11 12 13 15" # 一键配置HomeNAS（排除备份与恢复）
    [1]="0"
    [2]="submenu_2"
    [3]="submenu_3"
    [4]="submenu_4"
    [5]="submenu_5"
    [6]="15"
)

# 菜单项及其显示名称
declare -A menu_lines=(
    [0]="系统初始配置"
    [1]="安装面板Cockpit"
    [2]="安装虚拟机组件"
    [3]="外网访问Cockpit"
    [4]="删除外网访问配置"
    [5]="设置发送邮件账户"
    [6]="用户登录发送通知"
    [7]="取消用户登录通知"
    [8]="配置基础安全防护"
    [9]="安装防火墙服务"
    [10]="安装自动封锁服务"
    [11]="安装Docker"
    [12]="添加镜像地址"
    [13]="安装容器应用"
    [14]="备份与恢复"
    [15]="安装服务查询"
    [99]="一键配置HomeNAS"
)

declare -A submenus=(
    [submenu_2]="$submenu_2"
    [submenu_3]="$submenu_3"
    [submenu_4]="$submenu_4"
    [submenu_5]="$submenu_5"
)

# 子菜单对应的脚本索引
declare -A submenu_actions=(
    [submenu_2]="1 2 3 4"
    [submenu_3]="5 6 7"
    [submenu_4]="8 9 10"
    [submenu_5]="11 12 13 14"
)

# 启动脚本并显示欢迎信息和温馨提示信息
handle_main_menu
