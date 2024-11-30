#!/bin/bash

# 安装Fail2ban
apt install fail2ban -y

# 复制并配置jail.local
cp /etc/fail2ban/jail.{conf,local}
cat <<EOT | tee /etc/fail2ban/jail.local >/dev/null
#全局设置
[DEFAULT]

#此参数标识应被禁止系统忽略的 IP 地址。默认情况下，这只是设置为忽略来自机器本身的流量，这样您就不会填写自己的日志或将自己锁定。
ignoreip = 127.0.0.1/8 ::1

#此参数设置禁令的长度，以秒为单位。默认值为1h，值为"bantime  = -1"表示将永久禁止IP地址，设置值为1h，则禁止1小时。
bantime  = 1h

#此参数设置 Fail2ban 在查找重复失败的身份验证尝试时将关注的窗口。默认设置为 1d ，这意味着软件将统计最近 1 天内的失败尝试次数。
findtime  = 1d

#这设置了在禁止之前在窗口内允许的失败尝试次数。
maxretry = 5

#此条目指定 Fail2ban 将如何监视日志文件。设置auto意味着 fail2ban 将尝试pyinotify, 然后gamin, 然后基于可用的轮询算法。inotify是一个内置的 Linux 内核功能，用于跟踪文件何时被访问，并且是Fail2ban 使用pyinotify的 Python 接口。
#backend = auto
#Debian12使用systemd才能正常启动fail2ban
backend = systemd

#这定义了是否使用反向 DNS 来帮助实施禁令。将此设置为“否”将禁止 IP 本身而不是其域主机名。该warn设置将尝试查找主机名并以这种方式禁止，但会记录活动以供审查。
usedns = warn

#如果将您的操作配置为邮件警报，这是接收通知邮件的地址。
destemail = root@localhost

#发送者邮件地址
sender = root@<fq-hostname>

#这是用于发送通知电子邮件的邮件传输代理。
mta = mail

#“action_”之后的“mw”告诉 Fail2ban 向您发送电子邮件。“mwl”也附加了日志。
action = %(action_mw)s

#这是实施 IP 禁令时将丢弃的流量类型。这也是发送到新 iptables 链的流量类型。
protocol = tcp

##这里banaction必须用firewallcmd-ipset,这是fiewalll支持的关键，如果是用Iptables请不要这样填写
banaction = firewallcmd-ipset

[SSH]

enabled     = true
port        = ssh
filter      = sshd
logpath     = /var/log/auth.log
EOT

# 复制并配置mail-whois.local
cp /etc/fail2ban/action.d/mail-whois.{conf,local}
cat >/etc/fail2ban/action.d/mail-whois.local <<'EOT'
[INCLUDES]
before = mail-whois-common.conf

[Definition]
norestored = 1
actionstart = printf %%b "你好！\n监视到【<name>】服务已成功启动。\n敬请注意！\nFail2Ban"|mail -s "[Fail2Ban] <name>: 在 <fq-hostname> 服务器上启动" <dest>
actionstop = printf %%b "你好！\n监视到【<name>】服务已被停止。\n敬请注意！\nFail2Ban"|mail -s "[Fail2Ban] <name>: 在 <fq-hostname> 服务器上停止" <dest>
actioncheck =
actionban = printf %%b "警告!!!\n
            攻击者IP：<ip>\n
            被攻击机器名：$(uname -n) \n
            被攻击机器IP：$(/bin/curl -s ifconfig.co) \n
            攻击服务：<name> \n
            攻击次数：<failures> 次 \n
            攻击方法：暴力破解，尝试弱口令.\n
            该IP：<ip>已经被Fail2Ban加入防火墙黑名单,屏蔽时间<bantime>秒.\n
            以下是攻击者 <ip>信息 :\n
            $(/bin/curl -s https://api.vore.top/api/IPdata?ip=<ip>)\n
            Fail2Ban邮件提醒\n "|/bin/mailx -s "<fq-hostname>服务器:<name>服务疑似遭到<ip>暴力攻击。" <dest>
actionunban =
[Init]
name = default
dest = root
EOT

# 获取用户输入的邮件地址，如果未输入，则使用默认值
read -p "请输入接收Fail2ban告警通知邮箱账户: " dest_email
dest_email="${dest_email:-root@localhost}"

# 提取发送者邮箱地址
sender_email=$(awk -F ': ' '/^root:/ {print $2}' /etc/email-addresses)

# 如果在/etc/email-addresses文件中找不到root:内容，则使用默认值root@<fq-hostname>
if [[ -z "$sender_email" ]]; then
    sender_email="root@<fq-hostname>"
fi

# 输出提取通知发送邮箱地址
echo "Fail2ban告警通知发送邮箱账户: $sender_email"

# 输出接收Fail2ban告警通知邮箱账户
echo "Fail2ban告警通知接收邮箱账户: $dest_email"

# 替换配置文件中的邮箱地址
sed -i "s/destemail = .*/destemail = $dest_email/g" /etc/fail2ban/jail.local
sed -i "s/sender = .*/sender = $sender_email/g" /etc/fail2ban/jail.local

# 检查是否已配置防暴力攻击Cockpit Web登陆窗口，如果没有则配置
if ! grep -q "\[pam-generic\]" /etc/fail2ban/jail.d/defaults-debian.conf; then
    tee -a /etc/fail2ban/jail.d/defaults-debian.conf >/dev/null <<EOT
[pam-generic]
enabled = true
EOT
fi

# 启动Fail2ban
systemctl start fail2ban

echo "Fail2ban安装和配置完成！"
