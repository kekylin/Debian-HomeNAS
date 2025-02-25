#!/bin/bash

# ======================= 基础工具 =======================
# 定义颜色并映射消息类型
declare -A COLORS=(
    [INFO]='\033[0;36m'
    [SUCCESS]='\033[0;32m'
    [WARNING]='\033[0;33m'
    [ERROR]='\033[0;31m'
    [ACTION]='\033[0;34m'
    [WHITE]='\033[1;37m'
    [RESET]='\033[0m'
)

output() {
    local type="$1" msg="$2" custom_color="$3" is_log="${4:-false}"
    [[ -z "${COLORS[$type]}" ]] && type="INFO"
    local color="${custom_color:-${COLORS[$type]}}"
    if [ "$is_log" = true ]; then
        echo -e "${color}[${type}] ${msg}${COLORS[RESET]}"
    else
        echo -e "${color}${msg}${COLORS[RESET]}"
    fi
}

# ======================= 系统检测模块 =======================
SYSTEM="Unknown"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    SYSTEM="${ID^}"
elif [ -f /etc/debian_version ]; then
    SYSTEM="Debian"
fi
SYSTEM_LOWER="${SYSTEM,,}"
[[ "$SYSTEM_LOWER" != "debian" && "$SYSTEM_LOWER" != "ubuntu" ]] && output "WARNING" "未适配当前系统，继续可能存在错误" "" true

# ======================= 核心功能模块 =======================
# --- 元数据定义 ---
BASE_URLS=(
    "https://gitee.com/kekylin/Debian-HomeNAS/raw/test/Shell/"
    "https://raw.githubusercontent.com/kekylin/Debian-HomeNAS/refs/heads/test/Shell/"
)

declare -A SCRIPT_INFO=(
    ["c11"]="change_sources.sh|配置软件源"
    ["c12"]="install_required_software.sh|安装必备软件"
    ["c21"]="install_cockpit.sh|安装面板Cockpit"
    ["c22"]="install_virtualization.sh|安装虚拟机组件"
    ["c23"]="setup_cockpit_access.sh|外网访问Cockpit"
    ["c24"]="remove_cockpit_access.sh|删除外网访问配置"
    ["c31"]="email_config.sh|设置发送邮件账户"
    ["c32"]="login_notify.sh|用户登录发送通知"
    ["c33"]="cancel_login_notify.sh|取消用户登录通知"
    ["c41"]="system_security.sh|配置基础安全防护"
    ["c42"]="install_firewalld.sh|安装防火墙服务"
    ["c43"]="install_fail2ban.sh|安装自动封锁服务"
    ["c51"]="install_docker.sh|安装Docker"
    ["c52"]="dockerhub_mirror.sh|添加镜像地址"
    ["c53"]="deploy-containers.sh|安装容器应用"
    ["c54"]="docker_backup_restore.sh|备份与恢复"
    ["c61"]="install_tailscale.sh|内网穿透服务"
    ["c62"]="service_checker.sh|安装服务查询"
    ["c63"]="update_hosts.sh|自动更新hosts"
    ["u1"]="setup_network_manager.sh|设置Cockpit管理网络"
    ["d1"]="setup_network_manager.sh|设置Cockpit管理网络"
)

declare -a MAIN_MENU_ORDER=(
    "系统初始配置"
    "系统管理面板"
    "邮件通知服务"
    "系统安全防护"
    "Docker服务"
    "综合应用服务"
    "一键配置HomeNAS"
)

declare -A SUBMENU_ITEMS=(
    ["系统初始配置"]="c11 c12"
    ["系统管理面板"]="c21 c22 c23 c24"
    ["邮件通知服务"]="c31 c32 c33"
    ["系统安全防护"]="c41 c42 c43"
    ["Docker服务"]="c51 c52 c53 c54"
    ["综合应用服务"]="c61 c62 c63"
    ["一键配置HomeNAS"]="basic secure"
)

declare -A HOME_NAS_VERSIONS=(
    ["basic"]="c11 c12 c21 c51 c52 c53 c62"
    ["secure"]="c11 c12 c21 c31 c32 c41 c42 c43 c51 c52 c53 c62"
)

declare -A SYSTEM_SPECIFIC_SUBMENU=(
    ["Ubuntu"]="系统管理面板:u1"
    ["Debian"]="系统管理面板:d1"
)

# --- 通用工具函数 ---
get_chinese_desc() {
    local key="$1"
    local full_info="${SCRIPT_INFO[$key]}"
    IFS='|' read -r _ desc <<< "$full_info"
    echo "$desc"
}

get_script_urls() {
    local key="$1"
    local script_name="${SCRIPT_INFO[$key]%%|*}"
    local subdir="common"
    [[ $key == u* ]] && subdir="ubuntu"
    [[ $key == d* ]] && subdir="debian"
    local urls=()
    for base in "${BASE_URLS[@]}"; do
        urls+=("${base}${subdir}/${script_name}")
    done
    echo "${urls[*]}"
}

validate_input() {
    local choice="$1" max="$2"
    [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 0 && choice <= max ))
}

# --- 脚本执行函数 ---
is_script_applicable() {
    local script="$1"
    if [[ "$script" == u* && "$SYSTEM_LOWER" == "ubuntu" ]] || \
       [[ "$script" == d* && "$SYSTEM_LOWER" == "debian" ]] || \
       [[ "$script" == c* ]]; then
        return 0
    else
        return 1
    fi
}

run_script() {
    local key="$1"
    if ! is_script_applicable "$key"; then
        output "ERROR" "脚本 \"${key}\" 不适用于当前系统 ($SYSTEM)" "" true
        return
    fi
    
    local script_name="${SCRIPT_INFO[$key]%%|*}"
    local chinese_desc=$(get_chinese_desc "$key")
    local urls=($(get_script_urls "$key"))
    local script_path="/tmp/${script_name}"
    local success=false

    for url in "${urls[@]}"; do
        local short_url=$([[ $url == *gitee* ]] && echo "Gitee" || echo "Github")
        output "INFO" "正在从 $short_url 下载 \"$chinese_desc\"，地址: $url" "" true
        local max_retries=2 retry_count=0
        while :; do
            if wget -q --connect-timeout=15 --timeout=30 "$url" -O "$script_path"; then
                chmod +x "$script_path"
                output "SUCCESS" "开始执行 \"$chinese_desc\"..." "" true
                bash "$script_path"
                success=true
                break
            else
                if (( retry_count >= max_retries )); then
                    output "ERROR" "$short_url 下载失败，切换地址重试..." "" true
                    break
                else
                    ((retry_count++))
                    output "WARNING" "下载失败，第 ${retry_count} 次重试..." "" true
                    sleep 1
                fi
            fi
        done
        [ "$success" = true ] && break
    done
    
    [ "$success" = false ] && output "ERROR" "所有下载地址均失败" "" true
    rm -f "$script_path"
}

run_homenas_config() {
    local version="$1"
    if [[ -z "${HOME_NAS_VERSIONS[$version]}" ]]; then
        output "ERROR" "无效版本选项: $version" "" true
        return
    fi
    for script in ${HOME_NAS_VERSIONS[$version]}; do
        run_script "$script"
    done
}

# --- 子菜单相关函数 ---
add_system_specific_to_submenu() {
    local system_scripts="${SYSTEM_SPECIFIC_SUBMENU[$SYSTEM]}"
    if [ -n "$system_scripts" ]; then
        IFS=' ' read -r -a entries <<< "$system_scripts"
        for entry in "${entries[@]}"; do
            IFS=':' read -r menu script <<< "$entry"
            if [[ -n "${SUBMENU_ITEMS[$menu]}" ]]; then
                SUBMENU_ITEMS[$menu]+=" $script"
            else
                output "WARNING" "子菜单 $menu 不存在，跳过 $script" "" true
            fi
        done
    fi
}

display_submenu() {
    local title="$1"
    local items=(${SUBMENU_ITEMS[$title]})
    output "INFO" "$title"
    output "INFO" "--------------------------------------------------"

    for i in "${!items[@]}"; do
        local item="${items[$i]}"
        if [[ "$item" == "basic" ]]; then
            output "WHITE" "$((i + 1))、基础版"
        elif [[ "$item" == "secure" ]]; then
            output "WHITE" "$((i + 1))、安全版"
        else
            output "WHITE" "$((i + 1))、$(get_chinese_desc "$item")"
        fi
    done
    output "WHITE" "0、返回"

    while true; do
        echo -ne "${COLORS[ACTION]}请选择操作: ${COLORS[RESET]}"
        read choice
        if validate_input "$choice" "${#items[@]}"; then
            if [[ "$choice" != "0" ]]; then
                local selected_item="${items[$((choice - 1))]}"
                if [[ "$selected_item" == "basic" || "$selected_item" == "secure" ]]; then
                    run_homenas_config "$selected_item"
                else
                    run_script "$selected_item"
                fi
            fi
            break
        else
            output "ERROR" "无效选择，请重新输入" "" true
        fi
    done
}

# ======================= 主程序模块 =======================
print_colored_text() {
    local system_name="${SYSTEM} HomeNAS"
    local texts=(
        "=================================================="
        "                 $system_name"
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
        case $i in
            0|10) color="INFO" ;;
            1|2|3|4) color="WHITE" ;;
            *) color="SUCCESS" ;;
        esac
        output "$color" "${texts[$i]}"
    done
}

main_menu() {
    local first_run=true
    add_system_specific_to_submenu
    
    while true; do
        $first_run && clear && first_run=false
        print_colored_text
        
        for i in "${!MAIN_MENU_ORDER[@]}"; do
            output "WHITE" "$((i + 1))、${MAIN_MENU_ORDER[$i]}"
        done
        output "WHITE" "0、退出"
        output "INFO" "=================================================="
        
        while true; do
            echo -ne "${COLORS[ACTION]}请选择操作: ${COLORS[RESET]}"
            read choice
            if validate_input "$choice" "${#MAIN_MENU_ORDER[@]}"; then
                if [ "$choice" -eq 0 ]; then
                    output "SUCCESS" "退出脚本" "" true
                    exit 0
                else
                    display_submenu "${MAIN_MENU_ORDER[$((choice - 1))]}"
                fi
                break
            else
                output "ERROR" "无效选择，请重新输入" "" true
            fi
        done
    done
}

main_menu
