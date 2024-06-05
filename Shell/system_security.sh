#!/bin/bash

# 1. 限制能su到root的用户
function configure_su_restrictions {
    # 检查是否已经配置了对应的参数
    if grep -q "sudo" /etc/pam.d/su; then
        echo "已配置su限制，跳过配置。"
    else
        # 在文件首行插入内容
        sed -i '1i auth required pam_wheel.so group=sudo' /etc/pam.d/su
        echo "已添加su限制配置。"
    fi
}

# 2. 超时自动注销活动状态和记录所有用户的登录和操作日志
function configure_timeout_and_logging {
    # 检查是否已经配置了对应的参数
    if grep -q "TMOUT\|history" /etc/profile; then
        echo "已配置超时和命令记录日志，跳过配置。"
    else
        # 追加内容到文件末尾
        cat << EOF >> /etc/profile

# 超时自动退出
TMOUT=180
# 在历史命令中启用时间戳
export HISTTIMEFORMAT="%F %T "
# 记录所有用户的登录和操作日志
history
USER=\`whoami\`
USER_IP=\`who -u am i 2>/dev/null| awk '{print \$NF}'|sed -e 's/[()]//g'\`
if [ "\$USER_IP" = "" ]; then
USER_IP=\`hostname\`
fi
if [ ! -d /var/log/history ]; then
mkdir /var/log/history
chmod 777 /var/log/history
fi
if [ ! -d /var/log/history/\${LOGNAME} ]; then
mkdir /var/log/history/\${LOGNAME}
chmod 300 /var/log/history/\${LOGNAME}
fi
export HISTSIZE=4096
DT=\`date +"%Y%m%d_%H:%M:%S"\`
export HISTFILE="/var/log/history/\${LOGNAME}/\${USER}@\${USER_IP}_\$DT"
chmod 600 /var/log/history/\${LOGNAME}/*history* 2>/dev/null
EOF
        echo "已添加超时和命令记录日志。"
        # 加载配置使其生效
        bash -c "source /etc/profile"
    fi
}

# 3. 用户登录系统发送邮件告警
function configure_login_notification {
    read -p "是否设置用户登录系统发送邮件告警？(y/n): " choice
    if [ "$choice" == "y" ]; then
        read -p "请输入邮箱地址: " email
        # 检查是否已存在/etc/pam.d/login-notifiy.sh配置文件
        if [ -f "/etc/pam.d/login-notifiy.sh" ]; then
            # 清空文件内容
            echo "" > /etc/pam.d/login-notifiy.sh
        else
            # 如果文件不存在，则新建
            touch /etc/pam.d/login-notifiy.sh
        fi
        # 插入脚本内容
        cat << EOF > /etc/pam.d/login-notifiy.sh
#!/bin/bash

export LANG="en_US.UTF-8"

[ "\$PAM_TYPE" = "open_session" ] || exit 0
{
echo "用户: \$PAM_USER"
echo "远程用户: \$PAM_RUSER"
echo "远程主机: \$PAM_RHOST"
echo "服务: \$PAM_SERVICE"
echo "终端: \$PAM_TTY"
echo "日期: \`date '+%Y年%m月%d日%H时%M分%S秒'\`"
echo "服务器: \`uname -s -n -r\`"
} | mail -s "注意! 用户\$PAM_USER正通过\$PAM_SERVICE服务登录\`hostname -s | awk '{print toupper(substr(\$0,1,1)) substr(\$0,2)}'\`系统" $email
EOF
        echo "已配置用户登录系统发送邮件告警。"
        # 修改权限
        chmod +x /etc/pam.d/login-notifiy.sh

        # 检查是否已经配置了对应的参数
        if grep -q "login-notifiy.sh" /etc/pam.d/common-session; then
            echo "已配置用户登录系统发送邮件告警，跳过配置。"
        else
            # 在/etc/pam.d/common-session配置文件末行追加内容
            echo "session optional pam_exec.so debug /bin/bash /etc/pam.d/login-notifiy.sh" >> /etc/pam.d/common-session
            echo "已添加用户登录系统发送邮件告警。"
        fi
    else
        # 如果用户选择不设置通知，则检查并删除已有的配置
        if grep -q "login-notifiy.sh" /etc/pam.d/common-session; then
            sed -i '/login-notifiy.sh/d' /etc/pam.d/common-session
            echo "已删除用户登录系统发送邮件告警配置。"
        else
            echo "未设置用户登录系统发送邮件告警，跳过配置。"
        fi
    fi
}

# 主函数
function main {
    configure_su_restrictions
    configure_timeout_and_logging
    configure_login_notification
}

# 执行主函数
main
