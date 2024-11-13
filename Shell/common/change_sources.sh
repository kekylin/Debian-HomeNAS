#!/bin/bash
# 北京外国语大学开源软件镜像站

set -e  # 遇到错误时终止脚本
set -u  # 使用未定义的变量时报错
set -o pipefail  # 管道命令中的错误会导致脚本失败

# 用于输出脚本日志的函数
log() {
    echo "[INFO] $1"
}

# 错误退出的函数
error_exit() {
    echo "[ERROR] $1"
    exit 1
}

# 检查是否是root权限运行
if [ "$(id -u)" -ne 0 ]; then
    error_exit "请使用root权限运行此脚本!"
fi

# 自动检测系统发行版
detect_system() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRIB=$ID
        VERSION=$VERSION_CODENAME
    else
        error_exit "无法识别操作系统版本。"
    fi
}

# 备份现有的软件源文件
backup_sources() {
    if [ -f /etc/apt/sources.list ]; then
        cp /etc/apt/sources.list /etc/apt/sources.list.bak
    fi

    if [ -f /etc/apt/sources.list.d/debian.sources ]; then
        cp /etc/apt/sources.list.d/debian.sources /etc/apt/sources.list.d/debian.sources.bak
    fi

    if [ -f /etc/apt/sources.list.d/ubuntu.sources ]; then
        cp /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list.d/ubuntu.sources.bak
    fi
}

# 清空现有的软件源文件内容
clear_sources() {
    > /etc/apt/sources.list
}

# 根据系统版本设置新的软件源
set_sources() {
    case "$DISTRIB" in
        debian)
            cat > /etc/apt/sources.list.d/debian.sources <<EOF
Types: deb
URIs: https://mirrors.bfsu.edu.cn/debian
Suites: $VERSION $VERSION-updates $VERSION-backports
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: https://mirrors.bfsu.edu.cn/debian-security
Suites: $VERSION-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
            ;;
        ubuntu)
            cat > /etc/apt/sources.list.d/ubuntu.sources <<EOF
Types: deb
URIs: https://mirrors.bfsu.edu.cn/ubuntu
Suites: $VERSION $VERSION-updates $VERSION-backports
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: https://mirrors.bfsu.edu.cn/ubuntu
Suites: $VERSION-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
            ;;
        *)
            error_exit "无法识别的系统版本或不支持的系统。"
            ;;
    esac
}

# 更新软件源
update_sources() {
    apt update || error_exit "软件源更新失败。"
}

# 主执行流程
main() {
    detect_system
    backup_sources
    clear_sources
    set_sources
    update_sources
    log "软件源更换完成！"
}

# 调用主执行函数
main
