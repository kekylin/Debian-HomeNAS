#!/bin/bash

# 配置su限制
function configure_su_restrictions {
    local pam_file="/etc/pam.d/su"
    if grep -q "pam_wheel.so" "$pam_file"; then
        echo "已配置su限制，跳过配置。"
    else
        sed -i '1i auth required pam_wheel.so group=sudo' "$pam_file"
        echo "已添加su限制配置。"
    fi
}

# 配置超时自动注销和记录用户操作日志
function configure_timeout_and_logging {
    local profile_file="/etc/profile"
    if grep -q "TMOUT\|history" "$profile_file"; then
        echo "已配置超时和命令记录日志，跳过配置。"
    else
        cat << EOF >> "$profile_file"

# 超时自动退出
TMOUT=900
# 在历史命令中启用时间戳
export HISTTIMEFORMAT="%F %T "
# 记录所有用户的登录和操作日志
history
USER=\$(whoami)
USER_IP=\$(who -u am i 2>/dev/null| awk '{print \$NF}'|sed -e 's/[()]//g')
if [ "\$USER_IP" = "" ]; then
    USER_IP=\$(hostname)
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
DT=\$(date +"%Y%m%d_%H:%M:%S")
export HISTFILE="/var/log/history/\${LOGNAME}/\${USER}@\${USER_IP}_\$DT"
chmod 600 /var/log/history/\${LOGNAME}/*history* 2>/dev/null
EOF
        echo "已添加超时和命令记录日志。"
        source "$profile_file"
    fi
}

# 主函数
function main {
    configure_su_restrictions
    configure_timeout_and_logging
}

# 执行主函数
main
