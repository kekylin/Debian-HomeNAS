#!/bin/bash

# ======================= 基础工具模块 =======================
# 定义终端颜色代码
declare -A color_codes=(
    ["info"]=$'\e[0;36m'    # 青色
    ["success"]=$'\e[0;32m' # 绿色
    ["warning"]=$'\e[0;33m' # 黄色
    ["error"]=$'\e[0;31m'   # 红色
    ["action"]=$'\e[0;34m'  # 蓝色
    ["white"]=$'\e[1;37m'   # 粗体白色
    ["reset"]=$'\e[0m'      # 重置颜色
)

# 打印格式化消息
# 参数: 类型, 消息内容, 自定义颜色(可选), 是否添加前缀(默认false)
print_message() {
    local type="${1}" msg="${2}" custom_color="${3}" is_log="${4:-false}"
    local color="${custom_color:-${color_codes[$type]}}"
    local prefix=""
    
    [[ -z "${color}" ]] && color="${color_codes[info]}"
    [[ "${is_log}" == "true" ]] && prefix="[${type^^}] "
    echo -e "${color}${prefix}${msg}${color_codes[reset]}"
}

# ======================= 常量定义模块 =======================
# 定义文件路径常量
email_config_file="/etc/exim4/notify_email"
cron_task_file="/etc/cron.d/update-check"

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
        print_message "error" "不支持的系统 (${system})，仅支持 Debian 和 Ubuntu" "" "true"
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

# 获取并验证邮箱配置
# 返回: 邮箱地址
get_email_config() {
    if [ ! -f "$email_config_file" ] || [ -z "$(cat "$email_config_file")" ]; then
        print_message "error" "未找到有效的邮箱配置，文件 ${email_config_file} 不存在或为空" "" "true"
        exit 1
    fi
    echo "$(cat "$email_config_file")"
}

# ======================= 报告生成模块 =======================
# 格式化更新列表
# 参数: 更新数据, 更新计数, 标题
format_update_list() {
    local updates="$1" count="$2" title="$3"
    [[ $count -gt 0 ]] && echo -e "\n${title}（${count}个）：\n$(echo -e "$updates" | awk '/^Inst/ {printf "● %s: [%s] → (%s\n", $2, $3, $4}')"
}

# 检测系统版本更新
# 返回: 系统版本更新信息（若有）
detect_major_version_update() {
    local current_version=$(cat /etc/debian_version 2>/dev/null || echo "未知")
    local release_info=$(apt-get -s dist-upgrade | grep -i "inst.*debian.*release")
    local system_name=$(get_system_name)
    
    if [[ -n "$release_info" ]]; then
        local new_version=$(echo "$release_info" | awk '{print $2}' | grep -o '[0-9]\+\.[0-9]\+')
        if [[ -n "$new_version" && "$new_version" != "$current_version" ]]; then
            echo -e "${system_name}: ${current_version} → ${new_version}"
        fi
    fi
}

# 构建报告内容
# 参数: 安全更新数据, 安全更新计数, 常规更新数据, 常规更新计数
build_report_content() {
    local security_update_list="$1" security_update_count="$2" regular_update_list="$3" regular_update_count="$4"
    local total=$((security_update_count + regular_update_count))
    local major_update_info=$(detect_major_version_update)
    
    echo -e "更新摘要："
    echo -e "总可用更新: ${total} 个 | 安全更新: ${security_update_count} 个 | 常规更新: ${regular_update_count} 个\n"
    echo -e "更新详情："
    [[ -n "$major_update_info" ]] && echo -e "系统版本更新:\n${major_update_info}\n"
    format_update_list "$security_update_list" "$security_update_count" "安全更新"
    format_update_list "$regular_update_list" "$regular_update_count" "常规更新"
    echo -e "\n检测时间: $(date +'%Y-%m-%d %H:%M:%S')"
}

# 运行更新检查并生成报告
run_update_check() {
    print_message "info" "正在生成系统更新报告" "" "true"
    apt-get update > /dev/null 2>&1
    full_update_list=$(apt-get upgrade -s)
    
    security_update_list=$(echo "$full_update_list" | grep -i security | grep '^Inst')
    security_update_count=$(echo "$security_update_list" | grep -c "^Inst")
    
    regular_update_list=$(echo "$full_update_list" | grep -v -i security | grep '^Inst')
    regular_update_count=$(echo "$regular_update_list" | grep -c "^Inst")
    
    report_content=$(build_report_content "$security_update_list" "$security_update_count" "$regular_update_list" "$regular_update_count")
}

# ======================= 邮件通知模块 =======================
# 发送邮件通知
send_email_notification() {
    local notify_email=$(get_email_config)
    local hostname=$(get_hostname)
    local major_update_info=$(detect_major_version_update)
    local update_types=()
    
    # 检测更新类型
    [[ -n "$major_update_info" ]] && update_types+=("系统版本")
    [[ $security_update_count -gt 0 ]] && update_types+=("安全")
    [[ $regular_update_count -gt 0 ]] && update_types+=("常规")
    
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
    
    print_message "info" "正在发送通知邮件至 ${notify_email}" "" "true"
    echo -e "$report_content" | mail -s "[${hostname} 更新通知] ${subject}" "$notify_email"
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
            *) print_message "error" "无效的操作选项，请重新选择" "" "true" ;;
        esac
    done
}

# 显示定时检测子菜单并处理用户选择
schedule_menu() {
    while true; do
        echo -e "---------------------\n1. 每日检测（12:00）\n2. 每周检测（周一12:00）\n3. 自定义定时检测\n0. 返回\n---------------------"
        read -p "请选择操作： " subchoice
        case $subchoice in
            1) set_cron_task "daily"; return ;;
            2) set_cron_task "weekly"; return ;;
            3) set_custom_cron_task; return ;;
            0) return ;;
            *) print_message "error" "无效的操作选项，请重新选择" "" "true" ;;
        esac
    done
}

# ======================= 定时任务模块 =======================
# 设置 cron 任务
# 参数: 任务类型 (daily/weekly)
set_cron_task() {
    local schedule=$1 cron
    local script_path=$(readlink -f "$0")
    
    rm -f "$cron_task_file" 2>/dev/null
    [[ "$schedule" == "daily" ]] && cron="0 12 * * *" || cron="0 12 * * 1"
    echo "$cron root $script_path --check" > "$cron_task_file"
    chmod 644 "$cron_task_file"
    systemctl restart cron
    [[ "$schedule" == "daily" ]] && print_message "success" "已设置每日检测任务" "" "true" || print_message "success" "已设置每周检测任务" "" "true"
    sleep 1
}

# 设置自定义 cron 任务
set_custom_cron_task() {
    local script_path=$(readlink -f "$0")
    local cron
    
    read -p "请输入 cron 表达式（示例：0 12 * * * 表示每日12:00）： " cron
    if [[ ! "$cron" =~ ^[0-9*]+[[:space:]][0-9*]+[[:space:]][0-9*]+[[:space:]][0-9*]+[[:space:]][0-9*]+$ ]]; then
        print_message "error" "无效的 cron 表达式，请输入正确格式" "" "true"
        sleep 1
        return
    fi
    
    rm -f "$cron_task_file" 2>/dev/null
    echo "$cron root $script_path --check" > "$cron_task_file"
    chmod 644 "$cron_task_file"
    systemctl restart cron
    print_message "success" "已设置自定义检测任务（${cron}）" "" "true"
    sleep 1
}

# 列出 cron 任务
list_cron_tasks() {
    if [ -f "$cron_task_file" ]; then
        print_message "info" "当前定时任务：\n$(cat "$cron_task_file")" "" "true"
    else
        print_message "info" "无定时任务" "" "true"
    fi
    sleep 2
}

# 移除 cron 任务
remove_cron_task() {
    rm -f "$cron_task_file" 2>/dev/null
    systemctl restart cron
    print_message "success" "已移除定时任务" "" "true"
    sleep 1
}

# ======================= 执行检测模块 =======================
# 执行更新检查并处理结果
execute_update_check() {
    verify_system_support
    run_update_check
    if [[ $security_update_count -gt 0 || $regular_update_count -gt 0 ]]; then
        send_email_notification
        print_message "success" "检测到更新，已发送通知邮件" "" "true"
    else
        print_message "info" "系统已是最新状态，无可用更新" "" "true"
    fi
    sleep 2
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
