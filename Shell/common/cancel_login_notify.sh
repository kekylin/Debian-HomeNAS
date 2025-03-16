#!/bin/bash

# ANSI颜色控制码
RED_COLOR="\033[31m"
GREEN_COLOR="\033[32m"
CYAN_COLOR="\033[36m"
RESET_COLOR="\033[0m"

# 输出日志信息
log() {
    local level="$1" message="$2" color
    case "${level^^}" in
        INFO)    color="$CYAN_COLOR"   ;;
        SUCCESS) color="$GREEN_COLOR"  ;;
        ERROR)   color="$RED_COLOR"    ;;
    esac
    echo -e "${color}[$level] $message${RESET_COLOR}" >&2
}

# 定义路径常量
readonly NOTIFY_SCRIPT="/etc/pam.d/login-notify.sh"  # 通知脚本文件
readonly PAM_CONFIG="/etc/pam.d/common-session"      # PAM配置文件

# 删除通知脚本文件
delete_notify_script() {
    if [[ -f "$NOTIFY_SCRIPT" ]]; then
        if rm -f "$NOTIFY_SCRIPT"; then
            echo "通知脚本文件已删除"
        else
            log "ERROR" "无法删除通知脚本文件: $NOTIFY_SCRIPT"
            exit 1
        fi
    else
        echo ""
    fi
}

# 删除PAM配置中的通知项
delete_pam_notify_entry() {
    local pam_line="session optional pam_exec.so debug /bin/bash $NOTIFY_SCRIPT"

    # 检查PAM配置文件是否可写
    if [[ ! -w "$PAM_CONFIG" ]]; then
        log "ERROR" "PAM配置文件不可写: $PAM_CONFIG"
        exit 1
    fi

    # 如果PAM配置中存在通知项，则直接删除
    if grep -F -q "$pam_line" "$PAM_CONFIG" 2>/dev/null; then
        if sed -i'' "/^$(echo "$pam_line" | sed 's/[\/&]/\\&/g')$/d" "$PAM_CONFIG"; then
            echo "PAM通知项已删除"
        else
            log "ERROR" "无法删除PAM通知项"
            exit 1
        fi
    else
        echo ""
    fi
}

# 主函数：取消用户登录通知
remove_login_notify() {
    local script_result pam_result status=""

    # 执行两个核心操作
    script_result=$(delete_notify_script)
    pam_result=$(delete_pam_notify_entry)

    # 组合操作结果
    if [[ -n "$script_result" && -n "$pam_result" ]]; then
        status="$script_result，$pam_result"
    elif [[ -n "$script_result" ]]; then
        status="$script_result"
    elif [[ -n "$pam_result" ]]; then
        status="$pam_result"
    fi

    # 输出最终状态
    if [[ -n "$status" ]]; then
        log "SUCCESS" "已取消用户登录通知: $status"
    else
        log "INFO" "未配置用户登录通知，已跳过"
    fi
}

# 运行主逻辑
remove_login_notify
