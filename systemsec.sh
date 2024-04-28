#!/bin/bash

# 检查配置文件中是否已经包含相同的内容
check_config() {
    local config_file="$1"
    local config_content="$2"
    
    if [ -f "$config_file" ]; then
        if grep -qFx "$config_content" "$config_file"; then
            echo "配置文件 '$config_file' 已经包含相同的配置，跳过操作。"
            return 0
        fi
    fi
    
    return 1
}

# 检查并追加配置到 /etc/profile 文件
append_to_profile() {
    local profile_file="/etc/profile"
    local profile_content="$(cat <<'EOF'
# 超时自动注销活动状态
TMOUT=180
# 在 history 命令中启用时间戳
export HISTTIMEFORMAT="%F %T "
# 记录所有用户的登录和操作日志
history
 USER=`whoami`
 USER_IP=`who -u am i 2>/dev/null| awk '{print $NF}'|sed -e 's/[()]//g'`
 if [ "$USER_IP" = "" ]; then
 USER_IP=`hostname`
 fi
 if [ ! -d /var/log/history ]; then
 mkdir /var/log/history
 chmod 777 /var/log/history
 fi
 if [ ! -d /var/log/history/${LOGNAME} ]; then
 mkdir /var/log/history/${LOGNAME}
 chmod 300 /var/log/history/${LOGNAME}
 fi
 export HISTSIZE=4096
 DT=`date +"%Y%m%d_%H:%M:%S"`
 export HISTFILE="/var/log/history/${LOGNAME}/${USER}@${USER_IP}_$DT"
 chmod 600 /var/log/history/${LOGNAME}/*history* 2>/dev/null

EOF
)"

    if check_config "$profile_file" "$profile_content"; then
        return
    fi

    echo "$profile_content" | sudo tee -a "$profile_file" > /dev/null
    source "$profile_file"
}

# 检查并创建登陆邮件通知告警脚本文件
create_login_notify_script() {
    local notify_script="/etc/pam.d/login-notifiy.sh"
    local notify_content="$(cat <<'EOF'
#!/bin/bash

export LANG="en_US.UTF-8"

[ "$PAM_TYPE" = "open_session" ] || exit 0
{
echo "用户: $PAM_USER"
echo "远程用户: $PAM_RUSER"
echo "远程主机: $PAM_RHOST"
echo "服务: $PAM_SERVICE"
echo "终端: $PAM_TTY"
echo "日期: $(date '+%Y年%m月%d日%H时%M分%S秒')"
echo "服务器: $(uname -s -n -r)"
} | mail -s "注意! 用户$PAM_USER正通过$PAM_SERVICE服务登录$(hostname -s | awk '{print toupper(substr($0,1,1)) substr($0,2)}')系统" user@yourdomain.com
EOF
)"

    if check_config "$notify_script" "$notify_content"; then
        return
    fi

    echo "$notify_content" | sudo tee "$notify_script" > /dev/null
    sudo chmod +x "$notify_script"
}

# 检查并编辑 common-session 文件
edit_common_session() {
    local common_session="/etc/pam.d/common-session"
    local session_config="session optional pam_exec.so debug /bin/bash /etc/pam.d/login-notifiy.sh"

    if check_config "$common_session" "$session_config"; then
        return
    fi

    echo "$session_config" | sudo tee -a "$common_session" > /dev/null
}

# 设置su限制的配置
set_su_limit() {
    local pam_su_file="/etc/pam.d/su"
    local pam_config="auth required pam_wheel.so group=sudo"

    # 检查是否已经存在相同的配置
    if grep -qFx "$pam_config" "$pam_su_file"; then
        echo "配置文件 '$pam_su_file' 已经包含相同的配置，跳过操作。"
        return
    fi

    # 在指定位置插入新配置
    if ! grep -qFx "$pam_config" "$pam_su_file"; then
        sudo sed -i '/^# The PAM configuration file for the Shadow `su'\'' service$/a '"$pam_config" "$pam_su_file"
        echo "已成功将配置插入到 $pam_su_file 文件中"
    fi
}

# 检查并设置登陆系统邮件通知
setup_login_notification() {
    local notify_script="/etc/pam.d/login-notifiy.sh"

    read -p "是否需要设置登陆邮件系统通知接收邮箱？(y/n): " answer
    if [ "$answer" == "y" ]; then
        read -p "请输入接收邮箱地址: " email
        sudo sed -i '1,$d' "$notify_script" # 清空文件内容
        sudo tee -a "$notify_script" > /dev/null <<EOF
#!/bin/bash

export LANG="en_US.UTF-8"

[ "\$PAM_TYPE" = "open_session" ] || exit 0
{
echo "用户: \$PAM_USER"
echo "远程用户: \$PAM_RUSER"
echo "远程主机: \$PAM_RHOST"
echo "服务: \$PAM_SERVICE"
echo "终端: \$PAM_TTY"
echo "日期: \$(date '+%Y年%m月%d日%H时%M分%S秒')"
echo "服务器: \$(uname -s -n -r)"
} | mail -s "注意! 用户\$PAM_USER正通过\$PAM_SERVICE服务登录\$(hostname -s | awk '{print toupper(substr(\$0,1,1)) substr(\$0,2)}')系统" $email
EOF
    fi
}

# 主程序入口
main() {
    append_to_profile
    create_login_notify_script
    edit_common_session
    set_su_limit
    setup_login_notification
}

# 执行主程序
main
