#!/bin/bash

# 使用 ANSI 颜色代码定义颜色
declare -A COLORS=(
    [RED]='\033[0;31m'
    [GREEN]='\033[0;32m'
    [YELLOW]='\033[0;33m'
    [BLUE]='\033[0;34m'
    [PURPLE]='\033[0;35m'
    [CYAN]='\033[0;36m'
    [WHITE]='\033[1;37m'
    [RESET]='\033[0m'
)

# 使用不同颜色区分消息类型
log_message() {
    local msg_type="$1"
    local msg="$2"
    local color="${3:-${COLORS[RESET]}}"  # 默认颜色为 RESET
    echo -e "${color}[${msg_type}] ${msg}${COLORS[RESET]}"
}

# 配置45Drives软件源（用于安装Navigator、File Sharing、Identities组件）
log_message "INFO" "配置45Drives软件源..." "${COLORS[CYAN]}"
curl -sSL https://repo.45drives.com/setup | bash
apt update

# 安装Cockpit及其附属组件（Navigator、File Sharing、Identities组件）
. /etc/os-release
log_message "INFO" "安装Cockpit及其附属组件..." "${COLORS[CYAN]}"
if apt install -y -t ${VERSION_CODENAME}-backports cockpit pcp python3-pcp cockpit-navigator cockpit-file-sharing cockpit-identities; then
    log_message "SUCCESS" "Cockpit及其附属组件安装成功。" "${COLORS[GREEN]}"
else
    log_message "ERROR" "Cockpit及其附属组件安装失败。" "${COLORS[RED]}"
    exit 1
fi

# 安装Tuned系统调优工具
apt install -y tuned

# 配置Cockpit调优
cockpit_conf="/etc/cockpit/cockpit.conf"
if [[ ! -f "$cockpit_conf" ]]; then
    mkdir -p /etc/cockpit
    cat <<EOF > "$cockpit_conf"
[Session]
IdleTimeout=15
Banner=/etc/cockpit/issue.cockpit

[WebService]
ProtocolHeader = X-Forwarded-Proto
ForwardedForHeader = X-Forwarded-For
LoginTo = false
LoginTitle = HomeNAS
EOF
    log_message "SUCCESS" "Cockpit调优配置完成。" "${COLORS[GREEN]}"
fi

# 配置Cockpit首页展示信息
cat <<EOF > /etc/motd
我们信任您已经从系统管理员那里了解了日常注意事项。总结起来无外乎这三点：
1、尊重别人的隐私。
2、输入前要先考虑(后果和风险)。
3、权力越大，责任越大。
EOF

# 配置Cockpit登录界面公告
issue_file="/etc/cockpit/issue.cockpit"
if [[ ! -f "$issue_file" ]]; then
    echo "DIY Home NAS Service" > "$issue_file"
fi

# 重启cockpit服务
systemctl try-restart cockpit
log_message "SUCCESS" "Cockpit安装及调优已完成。" "${COLORS[GREEN]}"
