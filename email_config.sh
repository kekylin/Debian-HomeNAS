#!/bin/bash

# 询问用户是否需要配置邮件发送服务
read -p "是否需要配置邮件发送服务？(y/n): " choice

# 如果用户回答不是 y，则跳过配置邮件发送服务操作
if [ "$choice" != "y" ]; then
    echo "已跳过配置邮件发送服务。"
    exit 0
fi

# 安装邮件发送服务exim4
sudo apt install exim4 -y

# 备份配置文件
sudo cp /etc/exim4/update-exim4.conf.conf /etc/exim4/update-exim4.conf.conf.backup
sudo cp /etc/exim4/passwd.client /etc/exim4/passwd.client.backup
sudo cp /etc/email-addresses /etc/email-addresses.backup

# 清空配置文件内容
sudo truncate -s 0 /etc/exim4/update-exim4.conf.conf
sudo truncate -s 0 /etc/exim4/passwd.client
sudo truncate -s 0 /etc/email-addresses

# 插入内容到/etc/exim4/update-exim4.conf.conf文件中
cat <<EOF | sudo tee -a /etc/exim4/update-exim4.conf.conf
dc_eximconfig_configtype='satellite'
dc_other_hostnames=''
dc_local_interfaces='127.0.0.1 ; ::1'
dc_readhost='qq.com'
dc_relay_domains=''
dc_minimaldns='false'
dc_relay_nets=''
dc_smarthost='smtp.qq.com:587'
CFILEMODE='644'
dc_use_split_config='false'
dc_hide_mailname='true'
dc_mailname_in_oh='true'
dc_localdelivery='mail_spool'
EOF

# 询问用户输入QQ邮件账户及授权密码
read -p "请输入QQ邮件账户: " qq_account
read -sp "请输入QQ邮件授权密码: " qq_password
echo

# 编辑/etc/exim4/passwd.client文件配置邮件发送账户
echo "qq-smtp.l.qq.com:$qq_account:$qq_password" | sudo tee -a /etc/exim4/passwd.client
echo "*.qq.com:$qq_account:$qq_password" | sudo tee -a /etc/exim4/passwd.client
echo "smtp.qq.com:$qq_account:$qq_password" | sudo tee -a /etc/exim4/passwd.client

# 编辑/etc/email-addresses文件，添加邮箱地址
echo "root: $qq_account" | sudo tee -a /etc/email-addresses

# 重启exim4服务
sudo service exim4 restart

# 检测exim4服务是否正常运行
if sudo service exim4 status | grep -q "active (running)"; then
    echo -e "\e[32m邮件发送服务已配置完成。\e[0m"
else
    echo -e "\e[31m邮件发送服务运行异常，请检查服务状态。\e[0m"
fi

# 提醒用户如果安装了防火墙，记得开放587端口
echo "如果安装了防火墙，请确保已开放587端口。"
