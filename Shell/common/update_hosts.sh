#!/bin/bash

# 定义颜色
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

# 日志输出函数
log_message() {
    local msg_type="$1"
    local msg="$2"
    local color="${3:-${COLORS[RESET]}}"
    echo -e "${color}[${msg_type}] ${msg}${COLORS[RESET]}"
}

# 设置hosts文件路径
HOSTS_FILE="/etc/hosts"
START_MARK="# Kekylin Hosts Start"
END_MARK="# Kekylin Hosts End"
NEW_HOSTS=""
DOWNLOAD_URLS=(
    "https://ghfast.top/https://raw.githubusercontent.com/kekylin/hosts/main/hosts"  # 主用地址
    "https://raw.githubusercontent.com/kekylin/hosts/main/hosts"  # 备用地址
)

# 更新hosts文件
update_hosts() {
    local url
    NEW_HOSTS=""

    # 尝试多个下载地址
    for url in "${DOWNLOAD_URLS[@]}"; do
        log_message "INFO" "尝试从 $url 下载 Hosts 文件..." "${COLORS[CYAN]}"
        
        # 使用curl并设置超时限制为15秒
        NEW_HOSTS=$(curl -s -k -L --max-time 15 "$url")
        
        # 检查是否下载成功，curl的返回码为0表示成功
        if [ $? -eq 0 ] && [ -n "$NEW_HOSTS" ]; then
            log_message "SUCCESS" "成功从 $url 下载 Hosts 文件。" "${COLORS[GREEN]}"
            break
        else
            log_message "ERROR" "从 $url 下载失败，尝试下一个地址..." "${COLORS[RED]}"
            NEW_HOSTS=""
        fi
    done

    # 如果没有成功下载内容，则退出，避免后续动作
    if [ -z "$NEW_HOSTS" ]; then
        log_message "ERROR" "所有下载地址均失败，未更新 Hosts 文件。" "${COLORS[RED]}"
        return 1  # 返回1表示失败，停止后续操作
    fi

    # 如果 hosts 文件中存在标记，则删除标记间内容
    if grep -q "$START_MARK" $HOSTS_FILE && grep -q "$END_MARK" $HOSTS_FILE; then
        sed -i "/$START_MARK/,/$END_MARK/d" $HOSTS_FILE
    fi

    # 更新文件内容
    if [ -z "$(tail -n 1 $HOSTS_FILE)" ]; then
        echo -e "$NEW_HOSTS" | sudo tee -a $HOSTS_FILE > /dev/null
    else
        echo -e "\n$NEW_HOSTS" | sudo tee -a $HOSTS_FILE > /dev/null
    fi
    log_message "SUCCESS" "Hosts文件更新完成！" "${COLORS[GREEN]}"
}

# 创建定时任务
create_cron_job() {
    USER_HOME=$(eval echo ~$USER)
    SCRIPT_PATH="$USER_HOME/.kekylin_hosts_update.sh"

    # 删除旧任务（如果存在）
    if crontab -l | grep -q "# Kekylin Hosts Update"; then
        log_message "INFO" "定时任务已存在，正在删除旧任务..." "${COLORS[YELLOW]}"
        crontab -l | grep -v "# Kekylin Hosts Update" | crontab -
    fi

    # 复制脚本到用户目录并创建新任务
    cp "$0" "$SCRIPT_PATH"
    cron_job="0 0,6,12,18 * * * /bin/bash $SCRIPT_PATH update_hosts # Kekylin Hosts Update"
    
    # 只有当下载成功时才创建定时任务
    if update_hosts; then
        (crontab -l 2>/dev/null; echo "$cron_job") | crontab -
        log_message "SUCCESS" "定时任务已创建，每天的0点、6点、12点和18点自动执行。" "${COLORS[GREEN]}"
    fi
}

# 查询定时任务
list_cron_jobs() {
    log_message "INFO" "定时任务如下：" "${COLORS[CYAN]}"
    crontab -l || log_message "INFO" "当前没有定时任务。" "${COLORS[RED]}"
}

# 菜单函数
menu() {
    echo -e "\n请选择操作："
    echo "1) 单次更新Hosts文件"
    echo "2) 定时更新Hosts文件"
    echo "3) 删除定时更新任务"
    echo "4) 查询定时任务"
    echo "0) 返回"
    
    read -p "请输入选择: " choice
    
    case $choice in
        1)
            log_message "INFO" "您选择了单次更新Hosts文件。" "${COLORS[BLUE]}"
            update_hosts
            ;;
        2)
            log_message "INFO" "您选择了定时更新Hosts文件。" "${COLORS[BLUE]}"
            create_cron_job
            ;;
        3)
            crontab -l | grep -v "# Kekylin Hosts Update" | crontab -
            log_message "SUCCESS" "定时任务已删除。" "${COLORS[RED]}"
            ;;
        4)
            list_cron_jobs
            ;;
        0)
            return 0
            ;;
        *)
            log_message "ERROR" "无效选择，请输入1、2、3、4或0。" "${COLORS[RED]}"
            ;;
    esac
}

# 如果是定时任务触发，直接更新hosts
if [[ "$1" == "update_hosts" ]]; then
    update_hosts
else
    menu
fi
