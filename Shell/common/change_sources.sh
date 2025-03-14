#!/bin/bash

# 启用严格模式以增强错误处理
set -euo pipefail

# 镜像源基础URL
MIRROR="https://mirrors.tuna.tsinghua.edu.cn"

# 日志函数，支持颜色输出
log() {
    local level="$1"
    local message="$2"
    local color

    case "$level" in
        ERROR) color='\e[31m' ;;
        INFO) color='\e[36m' ;;
        WARNING) color='\e[33m' ;;
        SUCCESS) color='\e[32m' ;;
        *) color='\e[0m' ;;
    esac

    echo -e "${color}[$level] $message\e[0m"
}

# 确保以 root 权限运行
[ "$EUID" -ne 0 ] && { log "ERROR" "请以 root 权限运行此脚本!"; exit 1; }

log "INFO" "开始更换软件源..."

# 检测系统类型和版本
[ -f "/etc/os-release" ] || { log "ERROR" "无法识别操作系统!"; exit 1; }
. "/etc/os-release"
DISTRIB="$ID"
VERSION="$VERSION_CODENAME"

# 备份指定文件
backup() {
    local file="$1"
    if [ -f "$file" ]; then
        local backup_file="${file}.$(date +%F_%T).bak"
        cp "$file" "$backup_file"
        cleanup_backups "${file}.*.bak"
    else
        log "WARNING" "文件 $file 不存在，无需备份"
    fi
}

# 清理过旧备份文件，仅保留最新三份
cleanup_backups() {
    local file_pattern="$1"
    local backups=($(ls -t $file_pattern 2>/dev/null))
    local count=${#backups[@]}

    if [ $count -gt 3 ]; then
        local to_delete=$((count - 3))
        for ((i=count-1; i>=count-to_delete; i--)); do
            rm -f "${backups[$i]}"
        done
    fi
}

# 注释sources.list文件，避免冲突
comment_out_file() {
    local file="$1"
    if [ -f "$file" ]; then
        if grep -vE '^\s*#' "$file" | grep -q '[^[:space:]]'; then
            sed -i 's/^/#/' "$file"
        fi
    fi
}

# 备份并注释现有软件源文件
SOURCES_LIST="/etc/apt/sources.list"
DISTRIB_SOURCES="/etc/apt/sources.list.d/${DISTRIB}.sources"

backup "$SOURCES_LIST"
backup "$DISTRIB_SOURCES"
comment_out_file "$SOURCES_LIST"

# 输出成功提示信息
log "INFO" "现有软件源文件已备份并注释"

# 配置新软件源
log "INFO" "配置 DEB822 格式软件源文件..."
case "$DISTRIB" in
    debian|ubuntu)
        COMPONENTS=$([ "$DISTRIB" = "debian" ] && echo "main contrib non-free non-free-firmware" || echo "main restricted universe multiverse")
        KEYRING=$([ "$DISTRIB" = "debian" ] && echo "/usr/share/keyrings/debian-archive-keyring.gpg" || echo "/usr/share/keyrings/ubuntu-archive-keyring.gpg")
        SECURITY_URI=$([ "$DISTRIB" = "debian" ] && echo "$MIRROR/debian-security" || echo "$MIRROR/ubuntu")

        SOURCES_FILE="/etc/apt/sources.list.d/${DISTRIB}.sources"
        cat > "$SOURCES_FILE" <<EOF
Types: deb
URIs: $MIRROR/${DISTRIB}
Suites: $VERSION $VERSION-updates $VERSION-backports
Components: $COMPONENTS
Signed-By: $KEYRING

Types: deb
URIs: $SECURITY_URI
Suites: $VERSION-security
Components: $COMPONENTS
Signed-By: $KEYRING
EOF

        # 验证新软件源文件是否生成成功
        if [ ! -f "$SOURCES_FILE" ]; then
            log "ERROR" "软件源文件 $SOURCES_FILE 生成失败!"
            exit 1
        fi
        ;;
    *)
        log "ERROR" "不支持的系统: $DISTRIB"; exit 1 ;;
esac

# 更新软件源
apt update && log "SUCCESS" "软件源更换完成。感谢清华大学开源软件镜像站！" || { log "ERROR" "软件源更新失败!"; exit 1; }
