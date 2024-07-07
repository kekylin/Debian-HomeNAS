#!/bin/bash

# 设置用户登录通知
function configure_login_notification {
    read -p "请输入接收通知邮箱地址: " email
    # 检查是否已存在/etc/pam.d/login-notify.sh配置文件
    if [ -f "/etc/pam.d/login-notify.sh" ]; then
        # 清空文件内容
        echo "" > /etc/pam.d/login-notify.sh
    else
        # 如果文件不存在，则新建
        touch /etc/pam.d/login-notify.sh
    fi
    # 插入脚本内容
    cat << EOF > /etc/pam.d/login-notify.sh
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
    # 修改权限
    chmod +x /etc/pam.d/login-notify.sh

    # 检查是否已经配置了对应的参数
    if ! grep -q "login-notify.sh" /etc/pam.d/common-session; then
        # 在/etc/pam.d/common-session配置文件末行追加内容
        echo "session optional pam_exec.so debug /bin/bash /etc/pam.d/login-notify.sh" >> /etc/pam.d/common-session
    fi
    echo "用户登录通知设置成功。"
}

# 执行配置用户登录通知函数
configure_login_notification
