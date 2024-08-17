#!/bin/bash

# 定义常量
WORK_DIR="debian-homenas"
COMPOSE_DIR="$WORK_DIR/docker-compose"

# 容器配置，格式为 容器名称=下载地址
declare -A containers=(
    [ddns-go]="https://gitee.com/kekylin/Debian-HomeNAS/raw/main/Docker%20Compose/ddns-go.yaml"
    [dockge]="https://gitee.com/kekylin/Debian-HomeNAS/raw/main/Docker%20Compose/dockge.yaml"
    [dweebui]="https://gitee.com/kekylin/Debian-HomeNAS/raw/main/Docker%20Compose/dweebui.yaml"
    [nginx-ui]="https://gitee.com/kekylin/Debian-HomeNAS/raw/main/Docker%20Compose/nginx-ui.yaml"
    [portainer]="https://gitee.com/kekylin/Debian-HomeNAS/raw/main/Docker%20Compose/portainer.yaml"
    [portainer_zh-cn]="https://gitee.com/kekylin/Debian-HomeNAS/raw/main/Docker%20Compose/portainer_zh-cn.yaml"
    [scrutiny]="https://gitee.com/kekylin/Debian-HomeNAS/raw/main/Docker%20Compose/scrutiny.yaml"
)

# 准备工作：检查并创建目录
prepare_directory() {
    [[ ! -d "$COMPOSE_DIR" ]] && mkdir -p "$COMPOSE_DIR"
}

# 检查容器安装状态
check_container_status() {
    docker inspect "$1" &> /dev/null && echo "已安装" || echo "未安装"
}

# 下载docker compose文件
download_compose_file() {
    [[ ! -f "$COMPOSE_DIR/$1.yaml" ]] && curl -sSL -o "$COMPOSE_DIR/$1.yaml" "$2"
}

# 安装容器
install_container() {
    local name=$1
    local url=$2
    if [[ "$(check_container_status "$name")" == "未安装" ]]; then
        download_compose_file "$name" "$url"
        docker compose -p "$name" -f "$COMPOSE_DIR/$name.yaml" up -d
    else
        echo "$name 已安装，跳过安装。"
    fi
}

# 显示菜单并处理用户输入（按照容器名称排序）
show_menu() {
    local choices=()
    echo "可安装容器应用："
    for name in "${!containers[@]}"; do
        choices+=("$name")
    done
    IFS=$'\n' sorted_choices=($(sort <<<"${choices[*]}"))
    unset IFS

    local index=1
    for name in "${sorted_choices[@]}"; do
        echo "$index. $name ($(check_container_status "$name"))"
        ((index++))
    done

    echo "99. 全部安装"
    echo "0. 退出"
    echo -n "请输入选择："
    read -r -a selected_choices

    if [[ "${#selected_choices[@]}" -eq 1 ]]; then
        case "${selected_choices[0]}" in
            0) exit 0 ;;
            99) selected_choices=($(seq 1 ${#sorted_choices[@]})) ;;
            *) ;;
        esac
    fi

    for choice in "${selected_choices[@]}"; do
        if [[ "$choice" -ge 1 && "$choice" -le "${#sorted_choices[@]}" ]]; then
            install_container "${sorted_choices[$((choice-1))]}" "${containers[${sorted_choices[$((choice-1))]}]}"
        else
            echo "无效选项：$choice，请重新输入。"
        fi
    done
}

# 主程序
main() {
    prepare_directory
    show_menu
}

main
