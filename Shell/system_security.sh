#!/bin/bash

# 1. 限制能su到root的用户
function configure_su_restrictions {
    # 检查是否已经配置了pam_wheel.so group=sudo
    if grep -q "^auth\s*required\s*pam_wheel.so\s*group=sudo" /etc/pam.d/su; then
        echo "已配置su限制，跳过操作。"
    else
        # 在文件首行插入内容
        sed -i '1i auth required pam_wheel.so group=sudo' /etc/pam.d/su
        echo "已添加su限制配置。"
    fi
}

# 2. 超时自动注销活动状态和记录所有用户的登录和操作日志
function configure_timeout_and_logging {
    # 检查是否已经配置了TMOUT和HISTTIMEFORMAT
    if grep -q "TMOUT=900" /etc/profile && grep -q "HISTTIMEFORMAT" /etc/profile; then
        echo "已配置超时和命令记录日志，跳过操作。"
    else
        # 追加内容到文件末尾
        cat << EOF >> /etc/profile

# 超时自动退出
TMOUT=900
# 在历史命令中启用时间戳
export HISTTIMEFORMAT="%F %T "
# 记录所有用户的登录和操作日志
history
USER=\`whoami\`
USER_IP=\`who -u am i 2>/dev/null | awk '{print \$NF}' | sed -e 's/[()]//g'\`
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
        # 重新加载配置使其生效
        source /etc/profile
    fi
}

# 主函数
function main {
    configure_su_restrictions
    configure_timeout_and_logging
}

# 执行主函数
main
