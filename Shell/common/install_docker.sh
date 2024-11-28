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

# 遇到错误时终止脚本
set -euo pipefail

# 检查系统版本并获取系统名称
. /etc/os-release
OS_NAME=$(echo "$NAME" | tr '[:upper:]' '[:lower:]')
VERSION_CODENAME=$(echo "$VERSION_CODENAME")

# 定义基础镜像源URL
BASE_MIRROR="https://mirrors.bfsu.edu.cn"

# 定义镜像源地址函数
get_docker_mirror() {
    case $OS_NAME in
        debian*)
            echo "${BASE_MIRROR}/docker-ce/linux/debian"
            ;;
        ubuntu*)
            echo "${BASE_MIRROR}/docker-ce/linux/ubuntu"
            ;;
        *)
            log_message "ERROR" "Unsupported OS" "${COLORS[RED]}"
            exit 1
            ;;
    esac
}

# 获取镜像源地址
log_message "INFO" "获取 Docker 镜像源地址..." "${COLORS[CYAN]}"
DOCKER_MIRROR=$(get_docker_mirror)

# 添加 Docker 的官方 GPG 密钥
log_message "INFO" "更新包列表并安装必要软件..." "${COLORS[CYAN]}"
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
log_message "INFO" "下载 Docker GPG 密钥..." "${COLORS[CYAN]}"
sudo curl -fsSL "${DOCKER_MIRROR}/gpg" -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# 将存储库添加到 Apt 源
log_message "INFO" "添加 Docker 存储库到 sources.list.d..." "${COLORS[CYAN]}"
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] ${DOCKER_MIRROR} \
$(. /etc/os-release && echo "${VERSION_CODENAME}") stable" | \
sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update

# 安装 Docker 函数
install_docker() {
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    if [ $? -ne 0 ]; then
        log_message "ERROR" "Docker 安装失败，请检查网络或依赖关系。" "${COLORS[RED]}"
        exit 1
    fi
}

# 安装最新版本 Docker
log_message "INFO" "安装 Docker..." "${COLORS[CYAN]}"
install_docker

# 添加第一个创建的用户（ID：1000）至docker组
log_message "INFO" "添加用户到 docker 组..." "${COLORS[CYAN]}"
first_user=$(awk -F: '$3>=1000 && $1 != "nobody" {print $1}' /etc/passwd | sort | head -n 1)
sudo usermod -aG docker "$first_user"

log_message "SUCCESS" "Docker 安装完成，用户 $first_user 已添加 docker 组。" "${COLORS[GREEN]}"
