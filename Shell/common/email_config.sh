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

# 关联数组：存储域名与 SMTP 服务器的映射关系
declare -A SMTP_MAP=(
    ["qq.com"]="smtp.qq.com:587"
)

# 用户输入提示函数
prompt_message() {
    echo -e "${CYAN_COLOR}[INPUT]${RESET_COLOR} $1"
}

# 安全文件写入函数
safe_write() {
    local file="$1" content="$2"
    echo "$content" > "$file" || { log_message "ERROR" "写入文件 $file 失败"; return 1; }
    return 0
}

# 验证发件邮箱格式与域名匹配
validate_sender_email() {
    local email="$1"
    if [[ "$email" =~ ^[a-zA-Z0-9._%+-]{1,64}@qq\.com$ && "${email##*@}" == "qq.com" ]]; then
        printf "%s" "${SMTP_MAP[qq.com]}"
        return 0
    else
        log_message "ERROR" "无效的 SMTP 发件邮箱地址，仅支持 qq.com 域名"
        return 1
    fi
}

# 生成 Exim4 邮件服务器配置文件
generate_exim_config() {
    local email_domain="$1" smarthost="$2"
    safe_write "/etc/exim4/update-exim4.conf.conf" "$(cat <<EOF
dc_eximconfig_configtype='satellite'
dc_other_hostnames=''
dc_local_interfaces='127.0.0.1 ; ::1'
dc_readhost='$email_domain'
dc_relay_domains=''
dc_minimaldns='false'
dc_relay_nets=''
dc_smarthost='$smarthost'
CFILEMODE='644'
dc_use_split_config='false'
dc_hide_mailname='true'
dc_mailname_in_oh='true'
dc_localdelivery='mail_spool'
EOF
)" || exit 1
    if ! update-exim4.conf >/dev/null 2>&1; then
        log_message "ERROR" "更新 Exim4 配置失败，可能会影响后续操作"
    fi
}

# 配置 SMTP 认证参数
configure_smtp_auth() {
    local email_domain="$1" email="$2" password="$3" notify_email="$4"
    safe_write "/etc/exim4/passwd.client" "*.$email_domain:${email}:${password}" || exit 1
    chown root:Debian-exim "/etc/exim4/passwd.client"
    chmod 640 "/etc/exim4/passwd.client"
    safe_write "/etc/email-addresses" "root: $email" || exit 1
    safe_write "/etc/exim4/notify_email" "$notify_email" || exit 1
    chmod 644 "/etc/exim4/notify_email"
}

# 重启 Exim4 邮件服务
restart_exim_service() {
    log_message "INFO" "正在重启 Exim4 邮件服务"
    if command -v systemctl >/dev/null 2>&1; then
        systemctl restart exim4 && systemctl is-active --quiet exim4 || { log_message "ERROR" "Exim4 服务重启失败"; exit 1; }
    elif command -v service >/dev/null 2>&1; then
        service exim4 restart || { log_message "ERROR" "Exim4 服务重启失败"; exit 1; }
    else
        log_message "ERROR" "未找到可用的服务管理工具"
        exit 1
    fi
    log_message "SUCCESS" "Exim4 服务运行状态已更新"
}

# 发送测试邮件
send_validation_email() {
    local notify_email="$1" sender_email="$2" smtp_server="$3"
    local os_name
    os_name="$(awk -F= '/^ID=/ {print $2}' /etc/os-release | sed 's/"//g' | { read name; echo "${name^}"; })"
    local app_name="${os_name}-HomeNAS"
    local email_content
    email_content=$(cat <<EOF
Subject: 来自 [${app_name}] 的测试邮件
To: ${notify_email}
From: ${sender_email}

恭喜！您已成功配置 [${app_name}] 的邮件通知功能。

• SMTP 发件服务器: ${smtp_server}
• 发件邮箱地址: ${sender_email}
• 通知接收邮箱: ${notify_email}
• 配置验证时间: $(date +"%Y-%m-%d %H:%M")

如需了解更多 [${app_name}] 使用方法，请访问 https://github.com/kekylin/Debian-HomeNAS

此邮件为系统自动发送，请勿直接回复。
EOF
    )
    log_message "INFO" "正在发送测试邮件"
    echo -e "$email_content" | exim -bm "$notify_email" && \
        log_message "SUCCESS" "测试邮件已成功发送至 ${notify_email}" || \
        { log_message "ERROR" "测试邮件发送失败，请查看 /var/log/exim4/mainlog"; exit 1; }
}

# 主控制流程
main() {
    [[ $EUID -ne 0 ]] && { log_message "ERROR" "此脚本需以 root 权限执行"; exit 1; }
    if ! command -v exim4 >/dev/null 2>&1; then
        log_message "ERROR" "未检测到 Exim4 组件，请执行 'apt install exim4' 进行安装"
        exit 1
    fi
    
    log_message "INFO" "开始 Exim4 邮件服务配置..."
    prompt_message "请输入 SMTP 发件邮箱地址（仅支持 QQ 域名邮箱）："
    local email smarthost
    while read -r email; do
        smarthost=$(validate_sender_email "$email")
        if [[ $? -eq 0 ]]; then
            break
        fi
        prompt_message "请输入有效的 QQ 邮箱地址："
    done
    
    local email_domain="${email##*@}"
    prompt_message "请输入 SMTP 服务授权密码："
    local password
    while read -rs password && [[ -z "$password" ]]; do
        log_message "ERROR" "SMTP 授权密码为必填项"
        prompt_message "请输入 SMTP 服务授权密码："
    done
    echo
    
    prompt_message "请输入系统通知接收邮箱地址："
    local notify_email
    while read -r notify_email && [[ ! "$notify_email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-Z]{2,}$ ]]; do
        log_message "ERROR" "通知邮箱地址格式无效或为空"
        prompt_message "请输入有效的通知接收邮箱地址："
    done
    
    generate_exim_config "$email_domain" "$smarthost"
    configure_smtp_auth "$email_domain" "$email" "$password" "$notify_email"
    restart_exim_service
    send_validation_email "$notify_email" "$email" "$smarthost"
    
    log_message "INFO" "服务配置信息：
• SMTP 发件服务器: ${smarthost}
• 发件邮箱地址: ${email}
• 通知接收邮箱: ${notify_email}
• 配置验证时间: $(date +'%Y-%m-%d %H:%M')"
    log_message "SUCCESS" "已完成 Exim4 邮件服务配置！"
}

main
