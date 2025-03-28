#!/bin/bash

# ======================= 基础工具模块 =======================
# 定义终端颜色代码
declare -A COLORS=(
    ["INFO"]=$'\e[0;36m'    # 青色
    ["SUCCESS"]=$'\e[0;32m' # 绿色
    ["WARNING"]=$'\e[0;33m' # 黄色
    ["ERROR"]=$'\e[0;31m'   # 红色
    ["ACTION"]=$'\e[0;34m'  # 蓝色
    ["WHITE"]=$'\e[1;37m'   # 粗体白色
    ["RESET"]=$'\e[0m'      # 重置颜色
)

# 输出带颜色消息
output() {
    local type="${1}" msg="${2}" custom_color="${3}" is_log="${4:-false}"
    local color="${custom_color:-${COLORS[$type]}}"
    local prefix=""
    
    if [[ -z "${color}" ]]; then
        echo "[DEBUG] 无效类型: ${type}，默认使用 INFO" >&2
        color="${COLORS[INFO]}"
    fi
    
    [[ "${is_log}" == "true" ]] && prefix="[${type}] "
    printf "%b%s%b\n" "${color}" "${prefix}${msg}" "${COLORS[RESET]}"
}

# ======================= 系统检测模块 =======================
# 检测当前操作系统类型
detect_system() {
    local system="Unknown"
    local system_lower=""
    
    if [[ -f "/etc/os-release" ]]; then
        source /dev/stdin <<< "$(grep -E '^ID=' /etc/os-release)"
        system="${ID^}"
    elif [[ -f "/etc/debian_version" ]]; then
        system="Debian"
    elif command -v "uname" >/dev/null; then
        system=$(uname -s)
    fi
    system_lower="${system,,}"
    
    [[ "${system_lower}" != "debian" && "${system_lower}" != "ubuntu" ]] && \
        output "WARNING" "未适配当前系统 (${system})，继续可能存在错误" "" "true"
    
    echo "${system} ${system_lower}"
}

# ======================= 核心功能模块 =======================
# 定义下载源映射
declare -A BASE_URL_MAP=(
    ["gitee"]="https://gitee.com/kekylin/Debian-HomeNAS/raw/main/Shell/"
    ["github"]="https://raw.githubusercontent.com/kekylin/Debian-HomeNAS/refs/heads/main/Shell/"
)

# 解析命令行参数
SOURCE="gitee"  # 默认值

while getopts "s:" opt; do
    case "${opt}" in
        s)
            SOURCE="${OPTARG}"
            ;;
        *)
            # getopts 会自动处理无效选项
            ;;
    esac
done

# 检查 SOURCE 是否有效
if [[ -z "${BASE_URL_MAP[$SOURCE]}" ]]; then
    SOURCE="github"
fi

# 定义脚本信息
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
    ["c61"]="service_checker.sh|安装服务查询"
    ["c62"]="install_tailscale.sh|内网穿透服务"
    ["c63"]="update_hosts.sh|自动更新hosts"
    ["u1"]="setup_network_manager.sh|设置Cockpit管理网络(Ubuntu)"
    ["d1"]="setup_network_manager.sh|设置Cockpit管理网络(Debian)"
    ["basic"]="|基础版"
    ["secure"]="|安全版"
)

# 定义主菜单顺序
declare -a MAIN_MENU_ORDER=(
    "系统初始配置"
    "系统管理面板"
    "邮件通知服务"
    "系统安全防护"
    "Docker服务"
    "综合应用服务"
    "一键配置HomeNAS"
)

# 定义子菜单项
declare -A SUBMENU_ITEMS=(
    ["系统初始配置"]="c11 c12"
    ["系统管理面板"]="c21 c22 c23 c24"
    ["邮件通知服务"]="c31 c32 c33"
    ["系统安全防护"]="c41 c42 c43"
    ["Docker服务"]="c51 c52 c53 c54"
    ["综合应用服务"]="c61 c62 c63"
    ["一键配置HomeNAS"]="basic secure"
)

# 定义一键配置版本
declare -A HOME_NAS_VERSIONS=(
    ["basic"]="c11 c12 c21 c51 c52 c61"
    ["secure"]="c11 c12 c21 c31 c32 c41 c42 c43 c51 c52 c61"
)

# 定义系统特定子菜单
declare -A SYSTEM_SPECIFIC_SUBMENU=(
    ["Ubuntu"]="系统管理面板:u1"
    ["Debian"]="系统管理面板:d1"
)

# 获取脚本中文描述
get_chinese_desc() {
    local key="${1}"
    local full_info="${SCRIPT_INFO[$key]}"
    local desc
    IFS='|' read -r _unused desc <<< "${full_info}"
    echo "${desc}"
}

# 获取脚本子目录
get_script_subdir() {
    local key="${1}"
    local subdir="common"
    [[ "${key}" == u* ]] && subdir="ubuntu"
    [[ "${key}" == d* ]] && subdir="debian"
    echo "${subdir}"
}

# 获取脚本下载 URL
get_script_url() {
    local key="${1}"
    local script_name="${SCRIPT_INFO[$key]%%|*}"
    local subdir=$(get_script_subdir "${key}")
    local base_url="${BASE_URL_MAP[$SOURCE]}"
    echo "${base_url}${subdir}/${script_name}"
}

# 验证用户输入
validate_input() {
    local choice="${1}" max="${2}"
    [[ "${choice}" =~ ^[0-9]+$ ]] || return 1
    (( choice >= 0 && choice <= max ))
}

# 检查脚本适用性
is_script_applicable() {
    local script="${1}" system_lower="${2}"
    if [[ "${script}" == u* && "${system_lower}" == "ubuntu" ]] || \
       [[ "${script}" == d* && "${system_lower}" == "debian" ]] || \
       [[ "${script}" == c* ]]; then
        return 0
    else
        return 1
    fi
}

# 下载并执行远程脚本
run_script() {
    local key="${1}" system="${2}" system_lower="${3}"
    local script_name="${SCRIPT_INFO[$key]%%|*}"
    local chinese_desc=$(get_chinese_desc "${key}")
    local url=$(get_script_url "${key}")
    local script_dir="/tmp/homenas_script"
    local script_path="${script_dir}/${script_name}"
    local success=false
    local short_url=$([[ "${url}" == *gitee* ]] && echo "Gitee" || echo "Github")
    local max_retries=2
    local retry_count=0

    if ! is_script_applicable "${key}" "${system_lower}"; then
        output "ERROR" "脚本 \"${key}\" 不适用于当前系统 (${system})" "" "true"
        return 1
    fi
    
    output "INFO" "正在从 ${short_url} 下载 \"${chinese_desc}\"，地址: ${url}" "" "true"
    
    while [[ "${retry_count}" -le "${max_retries}" ]]; do
        if wget -q --connect-timeout=15 --timeout=30 "${url}" -O "${script_path}"; then
            success=true
            break
        else
            ((retry_count++))
            if [[ "${retry_count}" -le "${max_retries}" ]]; then
                output "WARNING" "下载失败，第 ${retry_count} 次重试..." "" "true"
                sleep 1
            else
                output "ERROR" "下载失败，已达到最大重试次数，请检查网络。" "" "true"
            fi
        fi
    done
    
    if [[ "${success}" == "true" ]]; then
        chmod +x "${script_path}"
        output "SUCCESS" "开始执行 \"${chinese_desc}\"..." "" "true"
        bash "${script_path}" || return 1
    else
        return 1
    fi
}

# 执行一键配置 HomeNAS
run_homenas_config() {
    local version="${1}" system="${2}" system_lower="${3}"
    if [[ -z "${HOME_NAS_VERSIONS[$version]}" ]]; then
        output "ERROR" "无效版本选项: ${version}" "" "true"
        return 1
    fi
    for script in ${HOME_NAS_VERSIONS[$version]}; do
        run_script "${script}" "${system}" "${system_lower}" || return 1
    done
}

# 添加系统特定子菜单项
add_system_specific_to_submenu() {
    local system="${1}"
    local system_scripts="${SYSTEM_SPECIFIC_SUBMENU[$system]}"
    if [[ -n "${system_scripts}" ]]; then
        IFS=' ' read -r -a entries <<< "${system_scripts}"
        for entry in "${entries[@]}"; do
            IFS=':' read -r menu script <<< "${entry}"
            if [[ -n "${SUBMENU_ITEMS[$menu]}" ]]; then
                SUBMENU_ITEMS[$menu]+=" ${script}"
            else
                output "WARNING" "子菜单 ${menu} 不存在，跳过 ${script}" "" "true"
            fi
        done
    fi
}

# 显示菜单选项
display_menu_items() {
    local -a items=("${@}")
    local prefix_color="WHITE"
    local show_back="true"
    
    for i in "${!items[@]}"; do
        output "${prefix_color}" "$((i + 1))、$(get_chinese_desc "${items[$i]}")"
    done
    [[ "${show_back}" == "true" ]] && output "${prefix_color}" "0、返回"
}

# 显示子菜单并处理选择
display_submenu() {
    local title="${1}" system="${2}" system_lower="${3}"
    local items=(${SUBMENU_ITEMS[$title]})
    local choices choice_array c valid selected_items
    
    output "INFO" "${title}"
    output "INFO" "--------------------------------------------------"
    display_menu_items "${items[@]}"
    output "INFO" "支持单选、多选，空格分隔，如：1 2 3"
    
    while true; do
        printf "%b请选择操作: %b" "${COLORS[ACTION]}" "${COLORS[RESET]}"
        read -r choices || break
       

 [[ -z "${choices}" ]] && output "ERROR" "输入为空，请重新输入" "" "true" && continue
        [[ ! "${choices}" =~ ^[0-9\ ]+$ ]] && output "ERROR" "输入包含无效字符，仅支持数字和空格" "" "true" && continue
        
        IFS=' ' read -r -a choice_array <<< "${choices}"
        [[ " ${choice_array[*]} " =~ " 0 " ]] && break
        
        valid=true
        selected_items=()
        declare -A seen
        for c in "${choice_array[@]}"; do
            if ! validate_input "${c}" "${#items[@]}"; then
                valid=false
                break
            fi
            [[ "${c}" -eq 0 ]] && continue
            if [[ -z "${seen[$c]}" ]]; then
                seen[$c]=1
                selected_items+=("${items[$((c - 1))]}")
            fi
        done
        
        if [[ "${valid}" == "true" && ${#selected_items[@]} -gt 0 ]]; then
            for item in "${selected_items[@]}"; do
                if [[ "${item}" == "basic" || "${item}" == "secure" ]]; then
                    run_homenas_config "${item}" "${system}" "${system_lower}"
                else
                    run_script "${item}" "${system}" "${system_lower}"
                fi
            done
            break
        else
            output "ERROR" "包含无效选择，请重新输入" "" "true"
        fi
    done
}

# ======================= 主程序模块 =======================
# 显示提示文本
print_colored_text() {
    local system="${1}"
    local system_name="${system} HomeNAS"
    local texts=(
        "=================================================="
        "                 ${system_name}"
        "                                  QQ群：339169752"
        "作者：kekylin"
        "项目：https://github.com/kekylin/Debian-HomeNAS"
        "--------------------------------------------------"
        "温馨提示！"
        "·系统安装后首次运行，建议执行“一键配置HomeNAS”。"
        "·安装防火墙后重启一次系统再使用。"
        "·设置Cockpit管理网络可能导致IP变化，请手动执行。"
        "=================================================="
    )
    for i in "${!texts[@]}"; do
        case ${i} in
            0|10) color="INFO" ;;
            1|2|3|4) color="WHITE" ;;
            *) color="SUCCESS" ;;
        esac
        output "${color}" "${texts[$i]}"
    done
}

# 显示主菜单并处理选择
main_menu() {
    local system="${1}" system_lower="${2}"
    local first_run=true
    local choice
    
    add_system_specific_to_submenu "${system}"
    
    while true; do
        ${first_run} && clear && first_run=false
        print_colored_text "${system}"
        
        for i in "${!MAIN_MENU_ORDER[@]}"; do
            output "WHITE" "$((i + 1))、${MAIN_MENU_ORDER[$i]}"
        done
        output "WHITE" "0、退出"
        output "INFO" "=================================================="
        
        while true; do
            printf "%b请选择操作: %b" "${COLORS[ACTION]}" "${COLORS[RESET]}"
            read -r choice || break
            [[ -z "${choice}" ]] && output "ERROR" "输入为空，请重新输入" "" "true" && continue
            [[ ! "${choice}" =~ ^[0-9]+$ ]] && output "ERROR" "输入包含无效字符，仅支持数字" "" "true" && continue
            if validate_input "${choice}" "${#MAIN_MENU_ORDER[@]}"; then
                if [[ "${choice}" -eq 0 ]]; then
                    output "SUCCESS" "退出脚本" "" "true"
                    exit 0
                else
                    display_submenu "${MAIN_MENU_ORDER[$((choice - 1))]}" "${system}" "${system_lower}"
                fi
                break
            else
                output "ERROR" "无效选择，请重新输入" "" "true"
            fi
        done
    done
}

# ======================= 主程序入口 =======================
# 创建临时目录
if ! mkdir -p "/tmp/homenas_script"; then
    output "ERROR" "无法创建临时目录 /tmp/homenas_script，请检查权限" "" "true"
    exit 1
fi

# 设置信号捕获，退出时清理脚本文件
trap 'printf "\n"; output "WARNING" "用户中断脚本，正在退出..." "" "true"; rm -rf /tmp/homenas_script; exit 1' INT
trap 'rm -rf /tmp/homenas_script' EXIT

# 获取系统信息并启动主菜单
read -r system system_lower <<< "$(detect_system)"
main_menu "${system}" "${system_lower}"
