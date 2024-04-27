#!/bin/bash

# 超时自动注销活动状态
sudo sed -i '$ a\TMOUT=180' /etc/profile

# 记录所有用户的登录和操作日志
sudo tee -a /etc/profile > /dev/null <<'EOF'

# 启用 history 命令的时间戳
export HISTTIMEFORMAT="%F %T "

# 记录所有用户的登录和操作日志
history
USER=$(whoami)
USER_IP=$(who -u am i 2>/dev/null | awk '{print $NF}' | sed -e 's/[()]//g')
if [ "$USER_IP" = "" ]; then
    USER_IP=$(hostname)
fi
LOG_DIR="/var/log/history/$USER"
if [ ! -d "$LOG_DIR" ]; then
    mkdir -p "$LOG_DIR"
    chmod 300 "$LOG_DIR"
fi
export HISTSIZE=4096
DT=$(date +"%Y%m%d_%H:%M:%S")
export HISTFILE="$LOG_DIR/${USER}@${USER_IP}_$DT"
chmod 600 "$LOG_DIR/*history*" 2>/dev/null

# 使配置生效
source /etc/profile
EOF

# 生成登陆邮件通知告警脚本文件
sudo tee /etc/pam.d/login-notifiy.sh > /dev/null <<'EOF'
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
sudo chmod +x /etc/pam.d/login-notifiy.sh

# 编辑 common-session 文件并追加一行
sudo tee -a /etc/pam.d/common-session > /dev/null <<EOF
session optional pam_exec.so debug /bin/bash /etc/pam.d/login-notifiy.sh
EOF

# 询问用户是否需要设置登陆系统邮件通知
read -p "是否需要设置登陆邮件系统通知接收邮箱？(y/n): " answer
if [ "$answer" == "y" ]; then
    read -p "请输入接收邮箱地址: " email
    sudo sed -i "s/user@yourdomain.com/$email/" /etc/pam.d/login-notifiy.sh
fi
