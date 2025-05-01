#!/bin/bash

# ======================= 基础工具模块 =======================
# 定义终端输出颜色代码
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
# 参数: 类型, 消息内容, 自定义颜色(可选), 是否添加前缀(默认false)
output() {
    local type="${1}" msg="${2}" custom_color="${3}" is_log="${4:-false}"
    local color="${custom_color:-${COLORS[$type]}}"
    local prefix=""
    
    if [[ -z "${color}" ]]; then
        echo "[DEBUG] 无效类型: ${type}，默认使用 INFO" >&2
        color="${COLORS[INFO]}"
    fi
    
    [[ "${is_log}" == "true" ]] && prefix="[${type}] "
    printf "%s%s%s\n" "${color}" "${prefix}${msg}" "${COLORS[RESET]}"
}

# ======================= 常量定义模块 =======================
# 定义文件路径常量
email_config_file="/etc/exim4/notify_email"
cron_task_file="/etc/cron.d/system-update-checker"

# ======================= 通用函数模块 =======================
# 验证系统支持，仅支持 Debian 和 Ubuntu
verify_system_support() {
    local system
    if command -v lsb_release >/dev/null 2>&1; then
        system=$(lsb_release -is)
    else
        system=$(grep -oP '^ID=\K.*' /etc/os-release | tr -d '"')
    fi
    system=$(echo "$system" | tr '[:upper:]' '[:lower:]')
    
    if [[ "$system" != "debian" && "$system" != "ubuntu" ]]; then
        output "ERROR" "不支持的系统 (${system})，仅支持 Debian 和 Ubuntu" "" "true"
        exit 1
    fi
}

# 获取系统名称（debian 或 ubuntu）
get_system_name() {
    if command -v lsb_release >/dev/null 2>&1; then
        lsb_release -is
    else
        grep -oP '^ID=\K.*' /etc/os-release | tr -d '"'
    fi
}

# 获取主机名，若主机名为空则回退到系统名称
get_hostname() {
    local hostname=$(hostname 2>/dev/null)
    if [[ -z "$hostname" || "$hostname" == "(none)" ]]; then
        get_system_name
    else
        echo "$hostname"
    fi
}

# 验证并获取邮箱配置
# 返回: 邮箱地址
get_email_config() {
    if [ ! -f "$email_config_file" ] || [ -z "$(cat "$email_config_file")" ]; then
        output "ERROR" "未找到有效的邮箱配置，文件 ${email_config_file} 不存在或为空" "" "true"
        exit 1
    fi
    echo "$(cat "$email_config_file")"
}

# 设置脚本文件并赋予权限
# 返回: 0 (成功), 1 (失败)
setup_script_file() {
    local current_script=$(readlink -f "$0")
    USER_HOME=$(eval echo ~$USER)
    local script_path="$USER_HOME/.system-update-checker.sh"
    
    if [ "$current_script" != "$script_path" ]; then
        cp "$current_script" "$script_path" 2>/dev/null
        if [ $? -ne 0 ]; then
            output "ERROR" "无法复制脚本到 ${script_path}，请检查权限" "" "true"
            return 1
        fi
        chmod +x "$script_path" 2>/dev/null
    fi
    
    if [ ! -f "$script_path" ]; then
        output "ERROR" "脚本文件 ${script_path} 不存在，请确保脚本已正确复制" "" "true"
        return 1
    fi
    echo "$script_path"
    return 0
}

# 验证 cron 表达式
# 参数: cron 表达式
# 返回: 0 (有效), 1 (无效)
validate_cron_expression() {
    local cron="$1"
    local fields=($cron)
    
    if [ ${#fields[@]} -ne 5 ]; then
        output "ERROR" "Cron 表达式必须包含 5 个字段（分钟 小时 日 月 星期）" "" "true"
        return 1
    fi
    
    local minute="${fields[0]}" hour="${fields[1]}" day="${fields[2]}" month="${fields[3]}" weekday="${fields[4]}"
    local field ranges=("0-59" "0-23" "1-31" "1-12" "0-7")
    local i
    
    for i in {0..4}; do
        local value="${fields[$i]}" range="${ranges[$i]}"
        local min=${range%-*} max=${range#*-}
        
        # 检查基本格式：数字、*、范围、步长、列表
        if [[ "$value" =~ ^[0-9*]+(-[0-9]+)?(/[0-9]+)?$ || "$value" =~ ^[0-9]+(,[0-9]+)*$ || "$value" == "*" ]]; then
            if [[ "$value" != "*" ]]; then
                if [[ "$value" =~ ^([0-9]+)-([0-9]+)$ ]]; then
                    local start=${BASH_REMATCH[1]} end=${BASH_REMATCH[2]}
                    if [ "$start" -lt "$min" ] || [ "$end" -gt "$max" ] || [ "$start" -gt "$end" ]; then
                        output "ERROR" "字段 ${value} 超出范围 ${range}" "" "true"
                        return 1
                    fi
                elif [[ "$value" =~ ^([0-9]+)/([0-9]+)$ ]]; then
                    local start=${BASH_REMATCH[1]} step=${BASH_REMATCH[2]}
                    if [ "$start" -lt "$min" ] || [ "$start" -gt "$max" ] || [ "$step" -eq 0 ]; then
                        output "ERROR" "步长字段 ${value} 无效" "" "true"
                        return 1
                    fi
                elif [[ "$value" =~ ^([0-9]+)(,([0-9]+))*$ ]]; then
                    IFS=',' read -r -a numbers <<< "$value"
                    for num in "${numbers[@]}"; do
                        if [ "$num" -lt "$min" ] || [ "$num" -gt "$max" ]; then
                            output "ERROR" "列表值 ${num} 超出范围 ${range}" "" "true"
                            return 1
                        fi
                    done
                elif ! [[ "$value" =~ ^[0-9]+$ ]] || [ "$value" -lt "$min" ] || [ "$value" -gt "$max" ]; then
                    output "ERROR" "字段 ${value} 超出范围 ${range}" "" "true"
                    return 1
                fi
            fi
        else
            output "ERROR" "字段 ${value} 包含无效字符或格式" "" "true"
            return 1
        fi
    done
    return 0
}

# ======================= 报告生成模块 =======================
# 格式化更新列表
# 参数: 更新数据, 更新计数, 标题
format_update_list() {
    local updates="$1" count="$2" title="$3"
    [[ $count -gt 0 ]] && printf "%s\n%s\n" "${title}（${count}个）：" "$(echo -e "$updates" | awk '/^Inst/ {printf "● %s: [%s] → (%s\n", $2, $3, $4}')"
}

# 检测系统版本更新
# 返回: 系统版本更新信息（若有）
detect_major_version_update() {
    local system_name=$(get_system_name)
    local current_version
    
    if [[ "$system_name" == "Debian" ]]; then
        if [ -f /etc/debian_version ]; then
            current_version=$(cat /etc/debian_version)
        else
            current_version=$(grep -oP '^VERSION_ID="\K[0-9.]+' /etc/os-release || echo "未知")
        fi
    else  # Ubuntu
        if command -v lsb_release >/dev/null 2>&1; then
            current_version=$(lsb_release -rs)
        else
            current_version=$(grep -oP '^VERSION_ID="\K[0-9.]+' /etc/os-release || echo "未知")
        fi
    fi
    
    local release_info=$(apt-get -s dist-upgrade | grep -i "inst.*${system_name}.*release" -i)
    if [[ -n "$release_info" ]]; then
        local new_version=$(echo "$release_info" | awk '{print $2}' | grep -o '[0-9]\+\.[0-9]\+')
        if [[ -n "$new_version" && "$new_version" != "$current_version" ]]; then
            echo -e "${system_name}: ${current_version} → ${new_version}"
        fi
    fi
}

# 生成报告内容
# 参数: 安全更新数据, 安全更新计数, 常规更新数据, 常规更新计数
build_report_content() {
    local security_update_list="$1" security_update_count="$2" regular_update_list="$3" regular_update_count="$4"
    local total=$((security_update_count + regular_update_count))
    local major_update_info=$(detect_major_version_update)
    
    printf "更新摘要：\n"
    printf "总可用更新: %s 个 | 安全更新: %s 个 | 常规更新: %s 个\n\n" "${total}" "${security_update_count}" "${regular_update_count}"
    printf "更新详情：\n"
    [[ -n "$major_update_info" ]] && printf "系统版本更新:\n%s\n" "${major_update_info}"
    format_update_list "$security_update_list" "$security_update_count" "安全更新"
    [[ -n "$major_update_info" || $security_update_count -gt 0 ]] && printf "\n"
    format_update_list "$regular_update_list" "$regular_update_count" "常规更新"
    printf "\n检测时间: %s\n" "$(date +'%Y-%m-%d %H:%M:%S')"
    printf "\n如需了解更多 [Debian-HomeNAS] 使用方法，请访问 https://github.com/kekylin/Debian-HomeNAS\n\n此邮件为系统自动发送，请勿直接回复。\n"
}

# 执行更新检测并生成报告
run_update_check() {
    output "INFO" "正在生成系统更新报告" "" "true"
    apt-get update > /dev/null 2>&1
    full_update_list=$(apt-get upgrade -s)
    
    declare -g security_update_list=$(echo "$full_update_list" | grep -i security | grep '^Inst')
    declare -g security_update_count=$(echo "$security_update_list" | grep -c "^Inst")
    
    declare -g regular_update_list=$(echo "$full_update_list" | grep -v -i security | grep '^Inst')
    declare -g regular_update_count=$(echo "$regular_update_list" | grep -c "^Inst")
    
    declare -g report_content=$(build_report_content "$security_update_list" "$security_update_count" "$regular_update_list" "$regular_update_count")
}

# ======================= 邮件通知模块 =======================
# 发送邮件通知
send_email_notification() {
    local notify_email=$(get_email_config)
    local hostname=$(get_hostname)
    local major_update_info=$(detect_major_version_update)
    local update_types=()
    
    # 确定更新类型
    [[ -n "$major_update_info" ]] && update_types+=("'系统'")
    [[ $security_update_count -gt 0 ]] && update_types+=("'安全'")
    [[ $regular_update_count -gt 0 ]] && update_types+=("'常规'")
    
    # 生成动态主题
    local subject=""
    case "${#update_types[@]}" in
        1)
            subject="发现${update_types[0]}更新"
            ;;
        2)
            subject="发现${update_types[0]}与${update_types[1]}更新"
            ;;
        3)
            subject="发现${update_types[0]}、${update_types[1]}与${update_types[2]}更新"
            ;;
        *)
            subject="发现更新"
            ;;
    esac
    
    output "INFO" "正在发送通知邮件至 ${notify_email}" "" "true"
    echo -e "$report_content" | mail -s "[${hostname} 更新通知] ${subject}" "$notify_email"
}

# ======================= 执行检测模块 =======================
# 执行更新检测并处理结果
execute_update_check() {
    verify_system_support
    run_update_check
    if [[ $security_update_count -gt 0 || $regular_update_count -gt 0 ]]; then
        send_email_notification
        output "SUCCESS" "检测到更新，已发送通知邮件" "" "true"
    else
        output "INFO" "系统已是最新状态，无可用更新" "" "true"
    fi
    sleep 2
}

# ======================= 定时任务模块 =======================
# 配置 cron 定时任务
# 参数: 任务类型 (daily/weekly)
set_cron_task() {
    local schedule=$1 cron
    local script_path=$(setup_script_file) || return 1
    
    rm -f "$cron_task_file" 2>/dev/null
    [[ "$schedule" == "daily" ]] && cron="0 0 * * *" || cron="0 0 * * 1"
    echo "$cron root $script_path --check" > "$cron_task_file"
    chmod 644 "$cron_task_file"
    systemctl restart cron
    [[ "$schedule" == "daily" ]] && output "SUCCESS" "已设置每日检测任务" "" "true" || output "SUCCESS" "已设置每周检测任务" "" "true"
    sleep 1
}

# 配置自定义 cron 定时任务
set_custom_cron_task() {
    local script_path=$(setup_script_file) || return 1
    local cron
    
    read -p "请输入 cron 表达式（示例：0 0 * * * 表示每日00:00）： " cron
    validate_cron_expression "$cron" || return 1
    
    rm -f "$cron_task_file" 2>/dev/null
    echo "$cron root $script_path --check" > "$cron_task_file"
    chmod 644 "$cron_task_file"
    systemctl restart cron
    output "SUCCESS" "已设置自定义检测任务（${cron}）" "" "true"
    sleep 1
}

# 列出当前 cron 定时任务
list_cron_tasks() {
    if [ -f "$cron_task_file" ]; then
        output "INFO" "当前定时任务：$(cat "$cron_task_file")" "" "true"
    else
        output "INFO" "无定时任务" "" "true"
    fi
    sleep 2
}

# 移除 cron 定时任务
remove_cron_task() {
    USER_HOME=$(eval echo ~$USER)
    rm -f "$cron_task_file" 2>/dev/null
    rm -f "$USER_HOME/.system-update-checker.sh" 2>/dev/null
    systemctl restart cron
    output "SUCCESS" "已移除定时任务并删除关联脚本 ${USER_HOME}/.system-update-checker.sh" "" "true"
    sleep 1
}

# ======================= 菜单模块 =======================
# 显示主菜单并处理用户选择
main_menu() {
    verify_system_support
    while true; do
        echo -e "------------------------------\n1. 立即执行检测\n2. 设置定时检测\n3. 查看定时任务\n4. 移除定时任务\n0. 退出\n------------------------------"
        read -p "请选择操作： " choice
        case $choice in
            1) execute_update_check ;;
            2) schedule_menu ;;
            3) list_cron_tasks ;;
            4) remove_cron_task ;;
            0) exit 0 ;;
            *) output "ERROR" "无效的操作选项，请重新选择" "" "true" ;;
        esac
    done
}

# 显示定时检测子菜单并处理用户选择
schedule_menu() {
    while true; do
        echo -e "---------------------\n1. 每日检测（00:00）\n2. 每周检测（周一00:00）\n3. 自定义定时检测\n0. 返回\n---------------------"
        read -p "请选择操作： " subchoice
        case $subchoice in
            1) set_cron_task "daily"; return ;;
            2) set_cron_task "weekly"; return ;;
            3) set_custom_cron_task; return ;;
            0) return ;;
            *) output "ERROR" "无效的操作选项，请重新选择" "" "true" ;;
        esac
    done
}

# ======================= 主程序入口模块 =======================
# 主程序入口
case "$1" in
    "--check") 
        verify_system_support
        run_update_check
        if [[ $security_update_count -gt 0 || $regular_update_count -gt 0 ]]; then
            send_email_notification
        fi
        ;;
    *) main_menu ;;
esac
