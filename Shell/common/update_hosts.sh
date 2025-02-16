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

# 更新hosts文件
update_hosts() {
    NEW_HOSTS=$(curl -s -k -L https://ghfast.top/https://raw.githubusercontent.com/kekylin/hosts/main/hosts)

    if grep -q "$START_MARK" $HOSTS_FILE && grep -q "$END_MARK" $HOSTS_FILE; then
        sed -i "/$START_MARK/,/$END_MARK/d" $HOSTS_FILE
    fi

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
    (crontab -l 2>/dev/null; echo "$cron_job") | crontab -
    update_hosts
    log_message "SUCCESS" "定时任务已创建，每天的0点、6点、12点和18点自动执行。" "${COLORS[GREEN]}"
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
