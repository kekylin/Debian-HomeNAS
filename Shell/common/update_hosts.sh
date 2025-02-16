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

# 日志消息输出函数，支持不同颜色和类型
log_message() {
    local msg_type="$1"
    local msg="$2"
    local color="${3:-${COLORS[RESET]}}"  # 默认颜色为 RESET
    echo -e "${color}[${msg_type}] ${msg}${COLORS[RESET]}"
}

# 设置hosts文件路径和标记文本
HOSTS_FILE="/etc/hosts"
START_MARK="# Kekylin Hosts Start"
END_MARK="# Kekylin Hosts End"

# 下载新的hosts内容
download_new_hosts() {
    curl -s -k -L https://ghfast.top/https://raw.githubusercontent.com/kekylin/hosts/main/hosts
}

# 更新hosts文件
update_hosts() {
    local new_hosts=$(download_new_hosts)

    # 清理标记行之间的内容
    if grep -q "$START_MARK" $HOSTS_FILE && grep -q "$END_MARK" $HOSTS_FILE; then
        sed -i "/$START_MARK/,/$END_MARK/d" $HOSTS_FILE
    fi

    # 确保在文件末尾添加空白行后插入新内容
    if [ -z "$(tail -n 1 $HOSTS_FILE)" ]; then
        echo -e "$new_hosts" | sudo tee -a $HOSTS_FILE > /dev/null
    else
        echo -e "\n$new_hosts" | sudo tee -a $HOSTS_FILE > /dev/null
    fi

    log_message "SUCCESS" "Hosts文件更新完成！" "${COLORS[GREEN]}"
}

# 创建定时任务
create_cron_job() {
    # 检查是否已存在定时任务
    if crontab -l | grep -q "# Kekylin Hosts Update"; then
        log_message "INFO" "定时任务已存在，正在删除旧任务..." "${COLORS[YELLOW]}"
        # 删除旧的定时任务
        crontab -l | grep -v "# Kekylin Hosts Update" | crontab -
    fi

    # 创建新的定时任务
    local cron_job="0 0,6,12,18 * * * /bin/bash $0 # Kekylin Hosts Update"
    (crontab -l 2>/dev/null; echo "$cron_job") | crontab -

    log_message "SUCCESS" "定时任务已创建，更新将会在每天的0点、6点、12点和18点自动执行。" "${COLORS[GREEN]}"
}

# 删除定时任务
delete_cron_job() {
    crontab -l | grep -v "# Kekylin Hosts Update" | crontab -
    log_message "SUCCESS" "定时任务已删除。" "${COLORS[GREEN]}"
}

# 下载脚本到用户目录
save_script_to_user_home() {
    local user_home=$(eval echo ~$USER)
    local script_path="$user_home/update_hosts.sh"
    curl -s -o "$script_path" https://gitee.com/kekylin/Debian-HomeNAS/raw/main/Shell/common/update_hosts.sh
    log_message "INFO" "定时更新脚本保存在$script_path，请勿删除！" "${COLORS[CYAN]}"
}

# 菜单显示并处理用户输入
menu() {
    echo -e "\n请选择操作："
    echo "1) 单次更新Hosts文件"
    echo "2) 定时更新Hosts文件"
    echo "3) 删除定时更新任务"
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
            update_hosts  # 立即执行一次更新
            save_script_to_user_home  # 仅在创建定时任务时保存脚本
            ;;
        3)
            delete_cron_job
            ;;
        0)
            return 0  # 返回上一层级
            ;;
        *)
            log_message "ERROR" "无效选择，请输入1、2、3或0。" "${COLORS[RED]}"
            ;;
    esac
}

# 执行菜单操作
menu
