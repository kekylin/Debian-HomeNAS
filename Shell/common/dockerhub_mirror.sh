重构下面脚本，要求使用更少的代码量实现相同的功能。定义ANSI颜色代码和定义日志输出函数部分不需要做任何修改。

#!/bin/bash

# 定义ANSI颜色代码
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

# 定义日志输出函数
log_message() {
    local msg_type="$1"
    local msg="$2"
    local color="${3:-${COLORS[RESET]}}"  # 默认颜色为重置
    echo -e "${color}[${msg_type}] ${msg}${COLORS[RESET]}"
}

# Docker 镜像加速地址
MIRRORS=(
    "https://docker.1panel.live"
    "https://docker.ketches.cn"
    "https://hub.iyuu.cn"
)
DAEMON_JSON="/etc/docker/daemon.json"

# 函数：将数组转换为 JSON 数组字符串
array_to_json_array() {
    local arr=("$@")
    local json_array="[\n"
    local len=${#arr[@]}
    for ((i = 0; i < len; i++)); do
        json_array+="    \"${arr[i]}\""
        [[ $i -lt $((len - 1)) ]] && json_array+=","
        json_array+="\n"
    done
    json_array+="  ]"
    echo -e "$json_array"
}

# 函数：更新配置文件中的 registry-mirrors
update_registry_mirrors() {
    local new_mirrors=("$@")
    local existing_mirrors=()

    # 读取现有的镜像地址
    if [[ -f "$DAEMON_JSON" ]]; then
        while IFS= read -r line; do
            existing_mirrors+=("${line//\"/}")
        done < <(grep -oP '"https?://[^"]+"' "$DAEMON_JSON")
    else
        log_message "WARNING" "配置文件 $DAEMON_JSON 不存在，将创建新文件。" "${COLORS[YELLOW]}"
    fi

    # 添加新镜像地址，避免重复
    for mirror in "${new_mirrors[@]}"; do
        [[ ! " ${existing_mirrors[*]} " =~ " ${mirror} " ]] && existing_mirrors+=("$mirror")
    done

    # 生成新的 JSON 内容
    local updated_mirrors_json
    updated_mirrors_json=$(array_to_json_array "${existing_mirrors[@]}")

    # 更新配置文件
    log_message "INFO" "更新daemon.json配置文件..." "${COLORS[CYAN]}"
    echo -e "{\n  \"registry-mirrors\": $updated_mirrors_json\n}" > "$DAEMON_JSON"
}

# 函数：重启 Docker 服务
reload_and_restart_docker() {
    log_message "INFO" "重启 Docker 服务..." "${COLORS[CYAN]}"
    systemctl daemon-reload
    if ! systemctl restart docker; then
        log_message "ERROR" "重启 Docker 服务失败。" "${COLORS[RED]}"
        exit 1
    fi
}

# 主逻辑
update_registry_mirrors "${MIRRORS[@]}"
reload_and_restart_docker
log_message "SUCCESS" "Docker镜像加速地址配置已完成。" "${COLORS[GREEN]}"
