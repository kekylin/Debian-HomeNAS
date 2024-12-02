#!/bin/bash

# 使用 ANSI 颜色代码定义颜色
declare -A COLORS=(
    [RED]='\033[0;31m'
    [GREEN]='\033[0;32m'
    [YELLOW]='\033[0;33m'
    [BLUE]='\033[0;34m'
    [PURPLE]='\033[0;35m'
    [CYAN]='\033[0;36m'
    [WHITE]='\033[1;37m'
    [RESET]='\033[0m'
)

# 使用不同颜色区分消息类型
log_message() {
    local msg_type="$1"
    local msg="$2"
    local color="${3:-${COLORS[RESET]}}"  # 默认颜色为 RESET
    echo -e "${color}[${msg_type}] ${msg}${COLORS[RESET]}"
}

# 基础URL列表
BASE_URLS=(
    "https://gitee.com/kekylin/Debian-HomeNAS/raw/main/Shell/"
    "https://raw.githubusercontent.com/kekylin/Debian-HomeNAS/refs/heads/main/Shell/"
)

# 脚本信息
declare -A SCRIPT_INFO=(
    ["c11"]="change_sources.sh #配置软件源"
    ["c12"]="install_required_software.sh #安装必备软件"

    ["c21"]="install_cockpit.sh #安装面板Cockpit"
    ["c22"]="install_virtualization.sh #安装虚拟机组件"
    ["c23"]="setup_cockpit_access.sh #外网访问Cockpit"
    ["c24"]="remove_cockpit_access.sh #删除外网访问配置"

    ["c31"]="email_config.sh #设置发送邮件账户"
    ["c32"]="login_notify.sh #用户登录发送通知"
    ["c33"]="cancel_login_notify.sh #取消用户登录通知"

    ["c41"]="system_security.sh #配置基础安全防护"
    ["c42"]="install_firewalld.sh #安装防火墙服务"
    ["c43"]="install_fail2ban.sh #安装自动封锁服务"

    ["c51"]="install_docker.sh #安装Docker"
    ["c52"]="dockerhub_mirror.sh #添加镜像地址"
    ["c53"]="deploy-containers.sh #安装容器应用"
    ["c54"]="docker_backup_restore.sh #备份与恢复"

    ["c61"]="install_tailscale.sh #内网穿透服务"
    ["c62"]="service_checker.sh #安装服务查询"
    
    ["u1"]="setup_network_manager.sh #设置Cockpit管理网络"
)

# 主菜单顺序
MAIN_MENU_ORDER=( 
    "系统初始配置"
    "系统管理面板"
    "邮件通知服务"
    "系统安全防护"
    "Docker服务"
    "综合应用服务"
    "一键配置HomeNAS"
)

# 子菜单项及其对应脚本
declare -A SUBMENU_ITEMS=(
    ["系统初始配置"]="c11 c12"
    ["系统管理面板"]="c21 c22 c23 c24 u1"
    ["邮件通知服务"]="c31 c32 c33"
    ["系统安全防护"]="c41 c42 c43"
    ["Docker服务"]="c51 c52 c53 c54"
    ["综合应用服务"]="c61 c62"
    ["一键配置HomeNAS"]="basic secure"
)

# 一键配置HomeNAS的版本与脚本对应关系
declare -A HOME_NAS_VERSIONS=(
    ["basic"]="c11 c12 c21 c51 c52 c53 c62"
    ["secure"]="c11 c12 c21 c31 c32 c41 c42 c43 c51 c52 c53 c62"
)

# 获取脚本中文名称，下载脚本、执行脚本提示语使用
get_chinese_desc() {
    local key="$1"
    local full_info="${SCRIPT_INFO[$key]}"
    local chinese_desc=$(echo "$full_info" | cut -d'#' -f2- | xargs)
    if [[ -z "$chinese_desc" ]]; then
        chinese_desc="${full_info%% *}"
    fi
    echo "$chinese_desc"
}

# 获取脚本的完整URL列表
get_script_urls() {
    local key="$1"
    local script_name="$(echo "${SCRIPT_INFO[$key]}" | cut -d' ' -f1)"  # 提取脚本名称
    local subdir=""
    if [[ $key == c* ]]; then
        subdir="common"  # c开头的脚本属于common目录
    elif [[ $key == u* ]]; then
        subdir="ubuntu"  # u开头的脚本属于ubuntu目录
    else
        subdir="common"  # 其他情况默认为common目录
    fi
    local urls=()
    for base in "${BASE_URLS[@]}"; do
        urls+=("${base}${subdir}/${script_name}")  # 生成完整URL
    done
    echo "${urls[@]}"
}

# 下载并执行脚本
run_script() {
    local key="$1"
    local full_info="${SCRIPT_INFO[$key]}"
    local script_name="$(echo "$full_info" | cut -d' ' -f1)"  # 提取脚本名称
    local chinese_desc=$(get_chinese_desc "$key")  # 获取中文描述
    local urls=($(get_script_urls "$key"))  # 获取所有可能的URL
    local script_path="/tmp/$(basename "$script_name")"  # 脚本保存路径

    for url in "${urls[@]}"; do
        local short_url=""
        [[ $url == *gitee* ]] && short_url="Gitee"  # 判断URL来源
        [[ $url == *raw.githubusercontent* ]] && short_url="Github"

        log_message "INFO" "正在从 $short_url 下载 “$chinese_desc”... (${url})" "${COLORS[CYAN]}"

        if wget -q --timeout=5 "$url" -O "$script_path"; then  # 尝试下载
            chmod +x "$script_path"  # 赋予执行权限
            log_message "SUCCESS" "开始执行 “$chinese_desc”..." "${COLORS[GREEN]}"
            bash "$script_path"  # 执行脚本
            return  # 下载成功并执行后返回
        else
            log_message "ERROR" "$short_url 下载失败，切换地址重试..." "${COLORS[RED]}"
        fi
    done

    log_message "ERROR" "所有下载地址均失败，请检查网络或重新尝试。" "${COLORS[RED]}"
}

# 处理“一键配置HomeNAS”的基础版和安全版
run_homenas_config() {
    local version="$1"
    [[ -z "${HOME_NAS_VERSIONS[$version]}" ]] && log_message "ERROR" "无效版本选项: $version" "${COLORS[RED]}" && return  # 检查版本是否存在
    for script in ${HOME_NAS_VERSIONS[$version]}; do
        run_script "$script"  # 依次运行该版本所需的脚本
    done
}

# 显示二级菜单并处理选择
display_submenu() {
    local title="$1"
    local items=(${SUBMENU_ITEMS[$title]})
    echo -e "\n${COLORS[CYAN]}$title${COLORS[RESET]}"
    echo -e "${COLORS[CYAN]}--------------------------------------------------${COLORS[RESET]}"

    for i in "${!items[@]}"; do
        local item="${items[i]}"
        if [[ "$item" == "basic" ]]; then
            display_text="基础版"  # 特殊处理“基础版”
        elif [[ "$item" == "secure" ]]; then
            display_text="安全版"  # 特殊处理“安全版”
        else
            local chinese_desc=$(get_chinese_desc "$item")
            display_text="$chinese_desc"  # 其他项显示中文描述
        fi
        echo -e "${COLORS[WHITE]}$((i + 1))、${display_text}${COLORS[RESET]}"
    done
    echo -e "${COLORS[WHITE]}0、返回${COLORS[RESET]}"

    while true; do
        read -rp "请选择操作: " choice
        if [[ $choice =~ ^[0-9]+$ ]] && (( choice >= 0 && choice <= ${#items[@]} )); then
            if (( choice > 0 )); then
                local selected_item="${items[choice - 1]}"
                if [[ "$selected_item" == "basic" || "$selected_item" == "secure" ]]; then
                    run_homenas_config "$selected_item"  # 一键配置HomeNAS
                else
                    run_script "$selected_item"  # 执行普通脚本
                fi
            fi
            break
        else
            log_message "ERROR" "无效选择，请重新输入" "${COLORS[RED]}"
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
        if [[ $i -eq 0 || $i -eq 10 ]]; then
            color="${COLORS[CYAN]}"  # 第一行和第十一行使用青色
        elif [[ $i -ge 1 && $i -le 4 ]]; then
            color="${COLORS[WHITE]}"  # 第二到第五行使用白色
        elif [[ $i -ge 5 && $i -le 9 ]]; then
            color="${COLORS[GREEN]}"  # 第六到第十行使用绿色
        fi
        echo -e "${color}${texts[$i]}${COLORS[RESET]}"
    done
}

# 主菜单函数
main_menu() {
    local first_run=true
    while true; do
        $first_run && clear && first_run=false  # 首次运行时清屏
        print_colored_text  # 输出欢迎文本
        for i in "${!MAIN_MENU_ORDER[@]}"; do
            echo -e "${COLORS[WHITE]}$((i + 1))、${MAIN_MENU_ORDER[i]}${COLORS[RESET]}"  # 显示菜单选项
        done
        echo -e "${COLORS[WHITE]}0、退出${COLORS[RESET]}"
        echo -e "${COLORS[CYAN]}==================================================${COLORS[RESET]}"
        read -rp "请选择操作: " choice  # 读取用户选择
        if [[ $choice =~ ^[0-9]+$ ]] && (( choice >= 0 && choice <= ${#MAIN_MENU_ORDER[@]} )); then
            if (( choice == 0 )); then
                log_message "SUCCESS" "退出脚本" "${COLORS[GREEN]}"  # 选择0退出脚本
                exit 0
            else
                display_submenu "${MAIN_MENU_ORDER[choice - 1]}"  # 显示相应的子菜单
            fi
        else
            log_message "ERROR" "无效选择，请重新输入" "${COLORS[RED]}"  # 选择无效时提示错误
        fi
    done
}

# 执行脚本
main_menu
