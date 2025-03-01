#!/bin/bash

# 定义颜色
declare -A COLORS=(
    [RED]='\033[0;31m'
    [GREEN]='\033[0;32m'
    [CYAN]='\033[0;36m'
    [RESET]='\033[0m'
)

# 日志函数
log() {
    local type="$1" msg="$2" color="${COLORS[${3:-RESET}]}"
    echo -e "${color}[${type}] ${msg}${COLORS[RESET]}"
}

# 封装日志类型
info() { log "INFO" "$1" "CYAN"; }
success() { log "SUCCESS" "$1" "GREEN"; }
error() { log "ERROR" "$1" "RED"; exit 1; }

# 写入文件函数
write_file() {
    local file="$1" content="$2"
    echo "$content" > "$file" || error "写入文件 $file 失败"
}

# 检测系统类型，默认Debian
. /etc/os-release
SYSTEM_NAME=$([[ "$ID" == "ubuntu" ]] && echo "Ubuntu" || echo "Debian")

# 配置45Drives软件源
info "配置45Drives软件源..."
command -v lsb_release >/dev/null || apt install -y lsb-release || error "无法安装lsb-release"
curl -sSL https://repo.45drives.com/setup | bash || { [ -f /etc/apt/sources.list.d/45drives.sources ] || error "45Drives软件源配置失败"; }
apt update || error "软件源更新失败"

# 安装Cockpit及其组件
info "安装Cockpit及其组件..."
apt install -y -t ${VERSION_CODENAME}-backports \
    cockpit pcp python3-pcp cockpit-navigator cockpit-file-sharing cockpit-identities \
    tuned || error "Cockpit及其组件安装失败"

# Cockpit调优
mkdir -p /etc/cockpit
write_file "/etc/cockpit/cockpit.conf" \
"[Session]
IdleTimeout=15
Banner=/etc/cockpit/issue.cockpit

[WebService]
ProtocolHeader = X-Forwarded-Proto
ForwardedForHeader = X-Forwarded-For
LoginTo = false
LoginTitle = HomeNAS"

write_file "/etc/motd" \
"我们信任您已经从系统管理员那里了解了日常注意事项。总结起来无外乎这三点：
1、尊重别人的隐私。
2、输入前要先考虑(后果和风险)。
3、权力越大，责任越大。"

write_file "/etc/cockpit/issue.cockpit" \
"基于${SYSTEM_NAME}搭建HomeNAS！"

# 重启服务
systemctl try-restart cockpit || error "Cockpit服务重启失败"
success "Cockpit安装及调优已完成"
