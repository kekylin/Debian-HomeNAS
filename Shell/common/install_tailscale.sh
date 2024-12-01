#!/bin/bash

# 定义颜色
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

# 日志消息函数
log_message() {
    local msg_type="$1"
    local msg="$2"
    local color="${3:-${COLORS[RESET]}}"  # 默认颜色为 RESET
    echo -e "${color}[${msg_type}] ${msg}${COLORS[RESET]}"
}
# 检查系统类型
if [ -f /etc/lsb-release ]; then
    . /etc/lsb-release
    OS=$DISTRIB_ID
    CODENAME=$DISTRIB_CODENAME
elif [ -f /etc/debian_version ]; then
    OS=Debian
    CODENAME=$(awk '/VERSION_CODENAME=/' /etc/os-release | cut -d'=' -f2)
else
    log_message "ERROR" "不支持的系统" "${COLORS[RED]}"
    exit 1
fi

# 添加Tailscale的包签名密钥和存储库
log_message "INFO" "添加Tailscale密钥和存储库..." "${COLORS[CYAN]}"
if [ "$OS" == "Debian" ]; then
    curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
    curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.tailscale-keyring.list | sudo tee /etc/apt/sources.list.d/tailscale.list
elif [ "$OS" == "Ubuntu" ]; then
    curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.noarmor.gpg | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
    curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.tailscale-keyring.list | sudo tee /etc/apt/sources.list.d/tailscale.list
else
    log_message "ERROR" "不支持的系统" "${COLORS[RED]}"
    exit 1
fi

# 安装Tailscale
sudo apt-get update
log_message "INFO" "安装Tailscale..." "${COLORS[CYAN]}"
sudo apt-get install -y tailscale
log_message "SUCCESS" "Tailscale安装完成..." "${COLORS[GREEN]}"

# 连接到Tailscale网络
log_message "INFO" "运行以下命令启动Tailscale，复制输出的链接到浏览器中打开进行身份验证。" "${COLORS[CYAN]}"
echo ""  # 添加空行
log_message "启动命令" "sudo tailscale up" "${COLORS[PURPLE]}"
echo ""  # 添加空行
