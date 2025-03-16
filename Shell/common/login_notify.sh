#!/bin/bash

# ANSI 颜色控制码
RED_COLOR="\033[31m"
GREEN_COLOR="\033[32m"
BLUE_COLOR="\033[34m"
CYAN_COLOR="\033[36m"
YELLOW_COLOR="\033[33m"
RESET_COLOR="\033[0m"

# 日志输出函数，支持分级显示
log_message() {
    local type="${1^^}" message="$2" color
    case "$type" in
        INFO)    color="$CYAN_COLOR"   ;;
        SUCCESS) color="$GREEN_COLOR"  ;;
        ERROR)   color="$RED_COLOR"    ;;
        *)       color="$YELLOW_COLOR"; type="WARNING" ;;
    esac
    if [[ "$type" == "ERROR" || "$type" == "WARNING" ]]; then
        echo -e "${color}[$type] $message${RESET_COLOR}" >&2
    else
        echo -e "${color}[$type] $message${RESET_COLOR}"
    fi
}

# 路径常量，支持环境变量覆盖
readonly EMAIL_FILE="${EMAIL_FILE:-/etc/exim4/notify_email}"
readonly SCRIPT_FILE="${SCRIPT_FILE:-/etc/pam.d/login-notify.sh}"
readonly PAM_FILE="${PAM_FILE:-/etc/pam.d/common-session}"

# 处理错误并退出
exit_with_error() {
    log_message "ERROR" "$1"
    exit 1
}

# 检查并操作文件
manage_file() {
    local file="$1" action="$2" err_msg="$3"
    case "$action" in
        exists) [[ -f "$file" ]] || return 1 ;;
        clear)  : > "$file" || exit_with_error "$err_msg" ;;
        create) touch "$file" && chown root:root "$file" && chmod 700 "$file" || exit_with_error "$err_msg" ;;
    esac
}

# 验证邮箱地址格式
check_email() {
    local email="$1"
    [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]] || exit_with_error "邮箱地址格式不正确: $email"
}

# 配置用户登录告警
setup_login_alert() {
    local email

    # 读取并验证邮箱地址
    manage_file "$EMAIL_FILE" "exists" || exit_with_error "未找到邮箱配置文件: $EMAIL_FILE"
    read -r email < "$EMAIL_FILE" || exit_with_error "无法读取文件: $EMAIL_FILE"
    [[ -z "$email" ]] && exit_with_error "邮箱地址为空，请检查文件: $EMAIL_FILE"
    check_email "$email"
    log_message "INFO" "接收通知邮箱: $email"

    # 处理通知脚本文件
    if manage_file "$SCRIPT_FILE" "exists"; then
        manage_file "$SCRIPT_FILE" "clear" "无法清空文件: $SCRIPT_FILE"
    else
        manage_file "$SCRIPT_FILE" "create" "无法创建文件: $SCRIPT_FILE"
    fi

    # 写入通知脚本内容
    cat << EOF > "$SCRIPT_FILE" || exit_with_error "无法写入文件: $SCRIPT_FILE"
#!/bin/bash
export LANG="en_US.UTF-8"
[ "\$PAM_TYPE" = "open_session" ] || exit 0
{
    echo "To: $email"
    echo "Subject: 注意！\$PAM_USER通过\$PAM_SERVICE登录\$(hostname -s)"
    echo
    echo "登录事件详情:"
    echo "----------------"
    echo "用户:         \$PAM_USER"
    echo "远程用户:     \$PAM_RUSER"
    echo
    echo "远程主机:     \$PAM_RHOST"
    echo "服务:         \$PAM_SERVICE"
    echo "终端:         \$PAM_TTY"
    echo
    echo "日期:         \$(date '+%Y年%m月%d日%H时%M分%S秒')"
    echo "服务器:       \$(uname -s -n -r)"
} | /usr/sbin/exim4 -t
EOF

    # 更新PAM配置文件
    [[ -w "$PAM_FILE" ]] || exit_with_error "文件不可写: $PAM_FILE"
    if ! grep -Fxq "session optional pam_exec.so debug /bin/bash $SCRIPT_FILE" "$PAM_FILE" 2>/dev/null; then
        echo "session optional pam_exec.so debug /bin/bash $SCRIPT_FILE" | tee -a "$PAM_FILE" >/dev/null || exit_with_error "无法更新文件: $PAM_FILE"
    fi

    log_message "SUCCESS" "用户登录通知配置完成！"
}

# 执行主逻辑
setup_login_alert
