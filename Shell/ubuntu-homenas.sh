#!/bin/bash

# 颜色定义
declare -A COLORS=(
    [RED]='\033[0;31m'
    [GREEN]='\033[0;32m'
    [CYAN]='\033[0;36m'
    [WHITE]='\033[1;37m'
    [RESET]='\033[0m'
)

# 设置基础 URL
BASE_URL_COMMON=(
    "https://gitee.com/kekylin/Debian-HomeNAS/raw/test/Shell/common"
    "https://raw.githubusercontent.com/kekylin/Debian-HomeNAS/refs/heads/test/Shell/common"
)

BASE_URL_UBUNTU=(
    "https://gitee.com/kekylin/Debian-HomeNAS/raw/test/Shell/ubuntu"
    "https://raw.githubusercontent.com/kekylin/Debian-HomeNAS/refs/heads/test/Shell/ubuntu"
)

# 定义主菜单顺序与分组
MAIN_MENU_ORDER=(
    "系统初始配置"
    "系统管理面板"
    "邮件通知服务"
    "系统安全防护"
    "Docker服务"
    "安装服务查询"
    "一键配置HomeNAS"
)

# 定义子菜单项及其对应脚本
declare -A SUBMENU_ITEMS=(
    ["系统初始配置"]="u1 c1"
    ["系统管理面板"]="u2 c2 c3 c4 u4"
    ["邮件通知服务"]="c5 c6 c7"
    ["系统安全防护"]="c8 c9 c10"
    ["Docker服务"]="u3 c11 c12 c13"
    ["安装服务查询"]="c14"
    ["一键配置HomeNAS"]="基础版 安全版"
)

# 定义脚本信息
declare -A SCRIPT_INFO=(
    ["c1"]="install_required_software.sh #安装必备软件"
    ["c2"]="install_virtualization.sh #安装虚拟机组件"
    ["c3"]="setup_cockpit_access.sh #外网访问Cockpit"
    ["c4"]="remove_cockpit_access.sh #删除外网访问配置"
    ["c5"]="email_config.sh #设置发送邮件账户"
    ["c6"]="login_notify.sh #用户登录发送通知"
    ["c7"]="cancel_login_notify.sh #取消用户登录通知"
    ["c8"]="system_security.sh #配置基础安全防护"
    ["c9"]="install_firewalld.sh #安装防火墙服务"
    ["c10"]="install_fail2ban.sh #安装自动封锁服务"
    ["c11"]="dockerhub_mirror.sh #添加镜像地址"
    ["c12"]="deploy-containers.sh #安装容器应用"
    ["c13"]="docker_backup_restore.sh #备份与恢复"
    ["c14"]="service_checker.sh #安装服务查询"
    ["u1"]="setup_software_sources.sh #配置软件源"
    ["u2"]="install_cockpit.sh #安装面板Cockpit"
    ["u3"]="install_docker.sh #安装Docker"
    ["u4"]="setup_network_manager.sh #设置Cockpit管理网络"
)

# 下载并执行脚本
run_script() {
    local key="$1"
    local script_name="${SCRIPT_INFO[$key]%% *}"
    local base_urls=()

    # 根据脚本类型选择相应的 BASE_URL
    if [[ $key == c* ]]; then
        base_urls=("${BASE_URL_COMMON[@]}")
    elif [[ $key == u* ]]; then
        base_urls=("${BASE_URL_UBUNTU[@]}")
    fi

    local script_path="/tmp/$(basename "$script_name")"

    for base_url in "${base_urls[@]}"; do
        local url="$base_url/$script_name"
        local short_url=""

        [[ $url == *gitee* ]] && short_url="gitee"
        [[ $url == *raw.githubusercontent* ]] && short_url="github"

        echo -e "${COLORS[CYAN]}正在从 $short_url 下载 $script_name... (${url})${COLORS[RESET]}"

        #  5 秒内未能建立连接，切换到下一个下载源。
        if wget -q --timeout=5 "$url" -O "$script_path"; then
            chmod +x "$script_path"
            echo -e "${COLORS[GREEN]}开始执行 $script_name...${COLORS[RESET]}"
            bash "$script_path"
            return
        else
            echo -e "${COLORS[RED]}$short_url 下载失败，切换地址重试...${COLORS[RESET]}"
        fi
    done

    echo -e "${COLORS[RED]}所有下载地址均失败，请检查网络或重新尝试。${COLORS[RESET]}"
}

# 处理“一键配置HomeNAS”的基础版和安全版
run_homenas_config() {
    local version="$1"

    # 定义每个版本对应的脚本
    declare -A VERSION_SCRIPTS=(
        ["基础版"]="u1 c1 u2 u3 c11 c12 c14"
        ["安全版"]="u1 c1 u2 c5 c6 c8 c9 c10 u3 c11 c12 c14"
    )

    # 参数检查：确保版本字符串有效
    if [[ -z "${VERSION_SCRIPTS[$version]}" ]]; then
        echo -e "${COLORS[RED]}无效版本选项: $version${COLORS[RESET]}"
        return
    fi

    # 执行对应版本的所有脚本
    for script in ${VERSION_SCRIPTS[$version]}; do
        run_script "$script"
    done
}

# 显示二级菜单并处理选择
display_submenu() {
    local title="$1"
    local items=(${SUBMENU_ITEMS[$title]})
    echo -e "\n$title"
    echo -e "${COLORS[CYAN]}--------------------------------------------------${COLORS[RESET]}"

    for i in "${!items[@]}"; do
        local display_name="${items[i]}"
        if [[ "$display_name" == "基础版" || "$display_name" == "安全版" ]]; then
            echo -e "${COLORS[WHITE]}$((i + 1))、${display_name}${COLORS[RESET]}"
        else
            echo -e "${COLORS[WHITE]}$((i + 1))、${SCRIPT_INFO[${display_name}]#*#}${COLORS[RESET]}"
        fi
    done
    echo -e "${COLORS[WHITE]}0、返回${COLORS[RESET]}"

    while true; do
        read -rp "请选择操作: " choice
        if [[ $choice =~ ^[0-9]+$ ]] && (( choice >= 0 && choice <= ${#items[@]} )); then
            if (( choice > 0 )); then
                local selected_item="${items[choice - 1]}"
                case "$selected_item" in
                    "基础版" | "安全版")
                        run_homenas_config "$selected_item"
                        ;;
                    *)
                        run_script "$selected_item"
                        ;;
                esac
            fi
            break
        else
            echo -e "${COLORS[RED]}无效选择，请重新输入${COLORS[RESET]}"
        fi
    done
}

# 输出文本函数
print_colored_text() {
    local texts=(
        "=================================================="
        "                 Ubuntu HomeNAS"
        "                                  QQ群：339169752"
        "作者：kekylin"
        "项目：https://github.com/kekylin/Debian-HomeNAS"
        "--------------------------------------------------"
        "温馨提示！"
        "1、系统安装后首次运行，建议执行“一键配置HomeNAS”。"
        "2、安装防火墙后重启一次系统再使用。"
        "3、设置Cockpit管理网络可能导致IP变化，请手动执行。"
        "=================================================="
    )

    for i in "${!texts[@]}"; do
        local color
        if (( i == 0 || i == 5 || i == 10 )); then
            color="${COLORS[CYAN]}"
        elif (( i >= 1 && i <= 4 )); then
            color="${COLORS[WHITE]}"
        else
            color="${COLORS[GREEN]}"
        fi
        echo -e "${color}${texts[$i]}${COLORS[RESET]}"
    done
}

# 主菜单函数
main_menu() {
    local first_run=true
    while true; do
        if $first_run; then
            clear  # 仅首次进入时清屏
            first_run=false
        fi
        
        print_colored_text

        for i in "${!MAIN_MENU_ORDER[@]}"; do
            echo -e "${COLORS[WHITE]}$((i + 1))、${MAIN_MENU_ORDER[i]}${COLORS[RESET]}"
        done
        echo -e "${COLORS[WHITE]}0、退出${COLORS[RESET]}"
        echo -e "${COLORS[CYAN]}==================================================${COLORS[RESET]}"

        read -rp "请选择操作: " choice
        if [[ $choice =~ ^[0-9]+$ ]] && (( choice >= 0 && choice <= ${#MAIN_MENU_ORDER[@]} )); then
            if (( choice == 0 )); then
                echo -e "${COLORS[GREEN]}退出脚本${COLORS[RESET]}"
                exit 0
            fi
            display_submenu "${MAIN_MENU_ORDER[choice - 1]}"
        else
            echo -e "${COLORS[RED]}无效选择，请重新输入${COLORS[RESET]}"
        fi
    done
}

# 执行脚本
main_menu
