#!/bin/bash

# 询问用户是否安装Fail2ban
read -p "是否安装防攻击程序Fail2ban？(y/n): " install_fail2ban

if [[ $install_fail2ban == "y" ]]; then
    # 安装Fail2ban
    sudo apt install fail2ban -y

    # 获取用户输入的邮件地址，如果未输入，则使用默认值
    read -p "请输入接收告警通知邮箱账户: " dest_email
    dest_email="${dest_email:-root@localhost}"

    # 提取发送者邮箱地址
    sender_email=$(awk '/root:/ {print $2}' /etc/email-addresses)

    # 替换配置文件中的邮箱地址
    sudo sed -i "s/destemail = .*/destemail = $dest_email/g" /etc/fail2ban/jail.local
    sudo sed -i "s/sender = root@<fq-hostname>/sender = $sender_email/g" /etc/fail2ban/jail.local

    # 创建并配置jail.local
    sudo cp /etc/fail2ban/jail.{conf,local}
    cat <<EOT | sudo tee /etc/fail2ban/jail.local >/dev/null
#全局设置
[DEFAULT]
ignoreip = 127.0.0.1/8 ::1
bantime  = -1
findtime  = 1d
maxretry = 3
backend = systemd
usedns = warn
destemail = $dest_email
sender = $sender_email
mta = mail
action = %(action_mw)s
protocol = tcp
banaction = firewallcmd-ipset

[SSH]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
EOT

    # 配置中文邮件格式
    sudo cp /etc/fail2ban/action.d/mail-whois.{conf,local}
    cat <<EOT | sudo tee /etc/fail2ban/action.d/mail-whois.local >/dev/null
# Fail2Ban configuration file
#
# Author: Cyril Jaquier
#
[INCLUDES]
before = mail-whois-common.conf

[Definition]
norestored = 1
actionstart = printf %%b "你好！\n监视到【<name>】服务已成功启动。\n敬请注意！\nFail2Ban"|mail -s "[Fail2Ban] <name>: 在 <fq-hostname> 服务器上启动" <dest>
actionstop = printf %%b "你好！\n监视到【<name>】服务已被停止。\n敬请注意！\nFail2Ban"|mail -s "[Fail2Ban] <name>: 在 <fq-hostname> 服务器上停止" <dest>
actioncheck =
actionban = printf %%b "警告!!!\n攻击者IP：<ip>\n被攻击机器名：$(uname -n) \n被攻击机器IP：$(/bin/curl ifconfig.co) \n攻击服务：<name> \n攻击次数：<failures> 次 \n攻击方法：暴力破解，尝试弱口令.\n该IP：<ip>已经被Fail2Ban加入防火墙黑名单,屏蔽时间<bantime>秒.\n\n以下是攻击者 <ip>信息 :\n$(/bin/curl https://ip.appworlds.cn?ip=\$ip)\n\nFail2Ban邮件提醒\n\n "|/bin/mailx -s "<fq-hostname>服务器:<name>服务疑似遭到<ip>暴力攻击。" <dest>
actionunban =
[Init]
name = default
dest = root
EOT

    # 检查是否已配置防暴力攻击Cockpit Web登陆窗口，如果没有则配置
    if ! grep -q "\[pam-generic\]" /etc/fail2ban/jail.d/defaults-debian.conf; then
        sudo tee -a /etc/fail2ban/jail.d/defaults-debian.conf >/dev/null <<EOT
[pam-generic]
enabled = true
EOT
    fi

    # 启动Fail2ban
    sudo systemctl start fail2ban

    echo "Fail2ban 安装和配置完成！"

elif [[ $install_fail2ban == "n" ]]; then
    echo "已跳过Fail2ban安装和配置。"
else
    echo "未做出选择，跳过Fail2ban安装和配置。"
fi
