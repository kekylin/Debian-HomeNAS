#!/bin/bash

# 遇到错误时终止脚本
set -euo pipefail

# 定义镜像源基础URL
MIRROR_BASE="https://mirrors.bfsu.edu.cn"

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

# 日志函数，带颜色输出
log() {
    local color=""
    case "$1" in
        ERROR) color="${COLORS[RED]}" ;;
        INFO) color="${COLORS[CYAN]}" ;;
        WARNING) color="${COLORS[YELLOW]}" ;;
        SUCCESS) color="${COLORS[GREEN]}" ;;
    esac
    echo -e "${color}[${1}] ${2}${COLORS[RESET]}"
}

# 检查是否以root权限运行
if [ "$EUID" -ne 0 ]; then
    log "ERROR" "请使用root权限运行此脚本!"
    exit 1
fi

log "INFO" "开始更换软件源。"

# 自动检测系统发行版
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRIB=$ID
    VERSION=$VERSION_CODENAME
else
    log "ERROR" "无法识别操作系统版本。"
    exit 1
fi

# 定义需要备份的文件
BACKUP_FILES=(
    /etc/apt/sources.list
    /etc/apt/sources.list.d/debian.sources
    /etc/apt/sources.list.d/ubuntu.sources
)

# 备份文件的函数
backup() {
    local file="$1"
    if [ -f "$file" ]; then
        cp "$file" "${file}.bak"
    fi
}

# 备份现有软件源文件
for FILE in "${BACKUP_FILES[@]}"; do
    backup "$FILE"
done

# 清空sources.list文件镜像源配置，避免冲突
truncate_file() {
    local file="$1"
    if [ -f "$file" ]; then
        > "$file"
    fi
}

truncate_file /etc/apt/sources.list

# 设置新的软件源配置
case "$DISTRIB" in
    debian)
        URIS="$MIRROR_BASE/debian"
        SUITES="$VERSION $VERSION-updates $VERSION-backports"
        COMPONENTS="main contrib non-free non-free-firmware"
        SECURITY_URI="$MIRROR_BASE/debian-security"
        SECURITY_SUITE="$VERSION-security"
        KEYRING="/usr/share/keyrings/debian-archive-keyring.gpg"
        ;;
    ubuntu)
        URIS="$MIRROR_BASE/ubuntu"
        SUITES="$VERSION $VERSION-updates $VERSION-backports"
        COMPONENTS="main restricted universe multiverse"
        SECURITY_URI="$MIRROR_BASE/ubuntu"
        SECURITY_SUITE="$VERSION-security"
        KEYRING="/usr/share/keyrings/ubuntu-archive-keyring.gpg"
        ;;
    *)
        log "ERROR" "无法识别的系统版本或不支持的系统。"
        exit 1
        ;;
esac

# 生成新的 DEB822 格式软件源配置文件
cat > "/etc/apt/sources.list.d/${DISTRIB}.sources" <<EOF
Types: deb
URIs: $URIS
Suites: $SUITES
Components: $COMPONENTS
Signed-By: $KEYRING

Types: deb
URIs: $SECURITY_URI
Suites: $SECURITY_SUITE
Components: $COMPONENTS
Signed-By: $KEYRING
EOF

# 更新软件源
if ! apt update; then
    log "ERROR" "软件源更新失败。"
    exit 1
fi

log "SUCCESS" "软件源更换完成!"
