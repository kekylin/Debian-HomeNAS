#!/bin/bash

# 取消用户登录通知
function remove_login_notification {
    # 检查并删除已有的配置
    if grep -q "login-notify.sh" /etc/pam.d/common-session; then
        sed -i '/login-notify.sh/d' /etc/pam.d/common-session
        echo "已取消用户登录通知。"
    else
        echo "未设置用户登录通知，跳过操作。"
    fi
}

# 执行取消用户登录通知函数
remove_login_notification
