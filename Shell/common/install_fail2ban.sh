#!/bin/bash

# ANSI颜色控制码定义
RED_COLOR="\033[31m"
GREEN_COLOR="\033[32m"
CYAN_COLOR="\033[36m"
YELLOW_COLOR="\033[33m"
RESET_COLOR="\033[0m"

# 日志输出函数，支持分级显示
log_message() {
    local type="${1^^}" message="$2" color
    case "$type" in
        "INFO")    color="$CYAN_COLOR"   ;;
        "SUCCESS") color="$GREEN_COLOR"  ;;
        "ERROR")   color="$RED_COLOR"    ;;
        *)         color="$YELLOW_COLOR"; type="WARNING" ;;
    esac
    echo -e "${color}[$type] $message${RESET_COLOR}" $([[ "$type" =~ ^(ERROR|WARNING)$ ]] && echo ">&2")
}

# 检查文件是否存在且可读
check_file() {
    local file="$1"
    if [[ ! -r "$file" ]]; then
        log_message "ERROR" "目标文件 $file 不存在或无读取权限"
        return 1
    fi
    return 0
}

# 安装Fail2ban软件包
install_fail2ban() {
    log_message "INFO" "正在安装Fail2ban软件包..."
    if ! apt install fail2ban -y; then
        log_message "ERROR" "Fail2ban安装失败，请检查软件源配置或网络连接状态"
        exit 1
    fi
    if ! dpkg -l | grep -q fail2ban; then
        log_message "ERROR" "Fail2ban安装验证未通过，可能未正确部署"
        exit 1
    fi
}

# 配置jail.local模块
configure_jail_local() {
    local config_file="/etc/fail2ban/jail.local"
    cp /etc/fail2ban/jail.{conf,local}
    cat > "$config_file" << EOF
#全局设置
[DEFAULT]

# 此参数标识应被禁止系统忽略的 IP 地址。默认情况下，这只是设置为忽略来自机器本身的流量，这样您就不会填写自己的日志或将自己锁定。
ignoreip = 127.0.0.1/8 ::1

# 此参数设置禁令的长度，以秒为单位。默认值为1h，值为"bantime  = -1"表示将永久禁止IP地址，设置值为1h，则禁止1小时。
bantime  = 1h

# 此参数设置 Fail2ban 在查找重复失败的身份验证尝试时将关注的窗口。默认设置为 1d ，这意味着软件将统计最近 1 天内的失败尝试次数。
findtime  = 1d

# 这设置了在禁止之前在窗口内允许的失败尝试次数。
maxretry = 5

# 此条目指定 Fail2ban 将如何监视日志文件。设置auto意味着 fail2ban 将尝试pyinotify, 然后gamin, 然后基于可用的轮询算法。inotify是一个内置的 Linux 内核功能，用于跟踪文件何时被访问，并且是Fail2ban 使用pyinotify的 Python 接口。
# backend = auto
# Debian12使用systemd才能正常启动fail2ban
backend = systemd

# 这定义了是否使用反向 DNS 来帮助实施禁令。将此设置为“否”将禁止 IP 本身而不是其域主机名。该warn设置将尝试查找主机名并以这种方式禁止，但会记录活动以供审查。
usedns = warn

# 如果将您的操作配置为邮件警报，这是接收通知邮件的地址。
destemail = $DEST_EMAIL

# 发送者邮件地址
sender = $SENDER_EMAIL

# 这是用于发送通知电子邮件的邮件传输代理。
mta = mail

# “action_”之后的“mw”告诉 Fail2ban 向您发送电子邮件。“mwl”也附加了日志。
action = %(action_mw)s

# 这是实施 IP 禁令时将丢弃的流量类型。这也是发送到新 iptables 链的流量类型。
protocol = tcp

# 这里banaction必须用firewallcmd-ipset,这是fiewalll支持的关键，如果是用Iptables请不要这样填写
banaction = firewallcmd-ipset

[SSH]

enabled     = true
port        = ssh
filter      = sshd
logpath     = /var/log/auth.log
EOF
    [[ $? -ne 0 ]] && { log_message "ERROR" "jail.local模块配置失败"; exit 1; }
}

# 配置mail-whois.local模块
configure_mail_whois() {
    local config_file="/etc/fail2ban/action.d/mail-whois.local"
    cp /etc/fail2ban/action.d/mail-whois.{conf,local}
    cat > "$config_file" << 'EOF'
[INCLUDES]
before = mail-whois-common.conf

[Definition]
norestored = 1
actionstart = printf %%b "• 主机名称：<fq-hostname>\n• 服务名称：<name>\n• 事件类型：服务启动\n• 触发时间：$(date "+%%Y-%%m-%%d %%H:%%M:%%S")\n如需获取更多信息，请登录服务器核查！\n\n本邮件由 Fail2Ban 自动发送，请勿直接回复！" | mail -s "[Fail2Ban] <fq-hostname> 主机 <name> 服务已启动！" <dest>
actionstop = printf %%b "• 主机名称：<fq-hostname>\n• 服务名称：<name>\n• 事件类型：服务停止\n• 触发时间：$(date "+%%Y-%%m-%%d %%H:%%M:%%S")\n如需获取更多信息，请登录服务器核查！\n\n本邮件由 Fail2Ban 自动发送，请勿直接回复！" | mail -s "[Fail2Ban] <fq-hostname> 主机 <name> 服务已停止！" <dest>
actioncheck =
actionban = printf %%b "安全警报！！！

            被攻击服务：<name>
            被攻击主机名称：$(uname -n)
            被攻击主机IP：$(/bin/curl -s ifconfig.co)

            攻击者IP：<ip>
            攻击次数：<failures> 次
            攻击方法：暴力破解，尝试弱口令。
            攻击者IP地址 <ip> 已经被 Fail2Ban 加入防火墙黑名单，屏蔽时间<bantime>秒。

            以下是攻击者 <ip> 信息 :
            $(/bin/curl -s https://api.vore.top/api/IPdata?ip=<ip>)
            
            本邮件由 Fail2Ban 自动发送，请勿直接回复！"|/bin/mailx -s "[Fail2Ban] <fq-hostname> 主机 <name> 服务疑似遭到暴力攻击！" <dest>
actionunban =
[Init]
name = default
dest = root
EOF
    [[ $? -ne 0 ]] && { log_message "ERROR" "mail-whois.local模块配置失败"; exit 1; }
}

# 配置通知邮箱地址并输出
configure_email() {
    # 定义文件路径和默认邮箱地址
    local notify_file="/etc/exim4/notify_email"       # 接收Fail2ban告警通知的邮箱配置文件
    local email_file="/etc/email-addresses"           # 发送者邮箱地址的配置文件
    local default_recipient="root@local-system"       # 默认接收告警通知邮箱地址
    local default_sender="root@system-hostname"       # 默认发送告警邮件的发件人邮箱地址

    # 获取接收告警通知邮箱地址
    if check_file "$notify_file"; then
        dest_email=$(sed 's/^[[:space:]]*//; s/[[:space:]]*$//' "$notify_file")
    else
        log_message "WARNING" "未找到 $notify_file，使用默认接收邮箱: $default_recipient"
        dest_email="$default_recipient"
    fi

    # 获取发送告警邮件的发件人邮箱地址
    if check_file "$email_file"; then
        sender_email=$(sed -n 's/^root:[[:space:]]*\(.*\)/\1/p' "$email_file" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        [[ -z "$sender_email" ]] && sender_email="$default_sender"
    else
        sender_email="$default_sender"
    fi

    # 将邮箱地址存储到全局变量
    DEST_EMAIL="$dest_email"
    SENDER_EMAIL="$sender_email"

    # 输出配置结果
    log_message "INFO" "接收告警通知邮箱: $dest_email"
    log_message "INFO" "告警邮件发件人邮箱: $sender_email"
}

# 配置pam-generic模块以保护Cockpit
configure_pam_generic() {
    local config_file="/etc/fail2ban/jail.d/defaults-debian.conf"
    if ! grep -q "\[pam-generic\]" "$config_file"; then
        echo -e "[pam-generic]\nenabled = true" >> "$config_file"
    fi
}

# 启动并启用Fail2ban服务
start_fail2ban() {
    if ! systemctl enable fail2ban >/dev/null 2>&1; then
        log_message "ERROR" "Fail2ban服务开机自启配置失败，请检查systemctl服务状态"
        exit 1
    fi
    log_message "INFO" "正在启动Fail2ban服务..."
    if ! systemctl start fail2ban >/dev/null 2>&1; then
        log_message "ERROR" "Fail2ban服务启动失败，请检查systemctl服务状态"
        exit 1
    fi
    log_message "SUCCESS" "Fail2ban服务已启动，并设置为开机自启"
}

# 主执行流程
main() {
    install_fail2ban
    configure_email
    configure_jail_local
    configure_mail_whois
    configure_pam_generic
    start_fail2ban
}

# 执行主函数
main
