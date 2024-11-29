#!/bin/bash

# 定义颜色
declare -A COLORS=(
    [RED]='\e[0;31m'
    [GREEN]='\e[0;32m'
    [YELLOW]='\e[0;33m'
    [CYAN]='\e[0;36m'
    [RESET]='\e[0m'
)

# 日志消息函数
log_message() {
    local msg_type="$1"
    local msg="$2"
    local color="${3:-${COLORS[RESET]}}"
    echo -e "${color}[${msg_type}] ${msg}${COLORS[RESET]}"
}

# 检查权限
if [ "$EUID" -ne 0 ]; then
    log_message "ERROR" "权限不足，请用root或sudo权限运行。" "${COLORS[RED]}"
    exit 1
fi

# 检查系统版本文件
if [ ! -f /etc/os-release ]; then
    log_message "ERROR" "无法识别系统发行版，退出。" "${COLORS[RED]}"
    exit 1
fi

# 读取系统ID
. /etc/os-release

# 定义主地址和备用地址
MAIN_BASE="https://tgitee.com/kekylin/Debian-HomeNAS/raw/main/Shell/"
BACKUP_BASE="https://traw.githubusercontent.com/kekylin/Debian-HomeNAS/refs/heads/main/Shell/"

# 获取来源名称的函数
get_source_name() {
    local url=$1
    if [[ $url == *gitee* ]]; then
        echo "Gitee"
    elif [[ $url == *github* ]]; then
        echo "Github"
    else
        echo "Unknown"
    fi
}

# 检查下载工具
if command -v wget >/dev/null 2>&1; then
    DL_CMD="wget --timeout=5 -qO-"
elif command -v curl >/dev/null 2>&1; then
    DL_CMD="curl -s -m 5"
else
    log_message "ERROR" "未安装wget或curl。" "${COLORS[RED]}"
    exit 1
fi

# 下载脚本函数
download_script() {
    local pri_url=$1
    local sec_url=$2
    local retry=2
    local urls=($pri_url $sec_url)
    local temp_file=$(mktemp)

    for (( i=0; i<=retry; i++ )); do
        for url in "${urls[@]}"; do
            if $DL_CMD "$url" > "$temp_file" 2>/dev/null; then
                source_name=$(get_source_name "$url")
                log_message "SUCCESS" "通过 $source_name 下载成功。" "${COLORS[GREEN]}"
                bash "$temp_file"
                rm -f "$temp_file"
                return
            else
                source_name=$(get_source_name "$url")
                log_message "WARNING" "通过 $source_name 下载失败，切换地址尝试..." "${COLORS[YELLOW]}"
            fi
        done
        if [ $i -lt $retry ]; then
            log_message "WARNING" "下载失败，积极重试中..." "${COLORS[YELLOW]}"
            sleep 1
        fi
    done

    log_message "ERROR" "重试 $i 次，所有下载地址均失败，请检查网络。" "${COLORS[RED]}"
    rm -f "$temp_file"
    exit 1
}

# 执行相应系统的脚本
case $ID in
    debian|ubuntu)
        script_name="${ID}-homenas.sh"
        main_url="${MAIN_BASE}${script_name}"
        backup_url="${BACKUP_BASE}${script_name}"
        log_message "INFO" "正在下载 $script_name 脚本..." "${COLORS[CYAN]}"
        download_script "$main_url" "$backup_url"
        ;;
    *)
        log_message "ERROR" "未支持的系统版本，退出。" "${COLORS[RED]}"
        exit 1
        ;;
esac
