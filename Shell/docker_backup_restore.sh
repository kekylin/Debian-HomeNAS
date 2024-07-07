#!/bin/bash

# 启动rsync服务
start_rsync() {
    systemctl start rsync
}

# 停止docker服务
stop_docker() {
    echo "停止docker服务..."
    systemctl stop docker.service docker.socket
    while systemctl is-active --quiet docker.service || systemctl is-active --quiet docker.socket; do
        echo "等待docker服务完全停止..."
        sleep 1
    done
    echo "Docker服务已完全停止。"
}

# 启动docker服务
start_docker() {
    echo "启动docker服务..."
    systemctl start docker.service docker.socket
}

# 使用rsync显示总进度的封装
rsync_with_progress() {
    rsync -a --info=progress2 --delete "$1" "$2"
}

# 获取目录大小
get_directory_size() {
    du -sh "$1" 2>/dev/null | awk '{print $1}'
}

# 获取文件数量
get_file_count() {
    find "$1" 2>/dev/null | wc -l
}

# 生成备份日志
generate_backup_log() {
    local log_file="$1"
    local start_time="$2"
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local src_dirs=("/var/lib/docker" "/etc/docker" "/opt/docker")
    local dest_dirs=("$3/var/lib/docker" "$3/etc/docker" "$3/opt/docker")

    {
        echo "备份日期: $(date '+%Y年%m月%d日 %H时%M分%S秒')"

        echo -e "\n备份源目录大小:"
        for dir in "${src_dirs[@]}"; do
            if [[ -d "$dir" ]]; then
                echo -e "$(get_directory_size "$dir")\t$dir"
            fi
        done

        echo -e "\n备份目的地目录大小:"
        for dir in "${dest_dirs[@]}"; do
            if [[ -d "$dir" ]]; then
                echo -e "$(get_directory_size "$dir")\t$dir"
            fi
        done

        echo -e "\n备份源文件数量:"
        for dir in "${src_dirs[@]}"; do
            if [[ -d "$dir" ]]; then
                echo -e "$(get_file_count "$dir")\t$dir"
            fi
        done

        echo -e "\n备份目的地文件数量:"
        for dir in "${dest_dirs[@]}"; do
            if [[ -d "$dir" ]]; then
                echo -e "$(get_file_count "$dir")\t$dir"
            fi
        done

        echo -e "\n操作用时: $duration 秒"
    } > "$log_file"
}

# 生成恢复日志
generate_restore_log() {
    local log_file="$1"
    local start_time="$2"
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local src_dirs=("$3/var/lib/docker" "$3/etc/docker" "$3/opt/docker")
    local dest_dirs=("/var/lib/docker" "/etc/docker" "/opt/docker")

    {
        echo "恢复日期: $(date '+%Y年%m月%d日 %H时%M分%S秒')"

        echo -e "\n恢复源目录大小:"
        for dir in "${src_dirs[@]}"; do
            if [[ -d "$dir" ]]; then
                echo -e "$(get_directory_size "$dir")\t$dir"
            fi
        done

        echo -e "\n恢复到目的地目录大小:"
        for dir in "${dest_dirs[@]}"; do
            if [[ -d "$dir" ]]; then
                echo -e "$(get_directory_size "$dir")\t$dir"
            fi
        done

        echo -e "\n恢复源文件数量:"
        for dir in "${src_dirs[@]}"; do
            if [[ -d "$dir" ]]; then
                echo -e "$(get_file_count "$dir")\t$dir"
            fi
        done

        echo -e "\n恢复到目的地文件数量:"
        for dir in "${dest_dirs[@]}"; do
            if [[ -d "$dir" ]]; then
                echo -e "$(get_file_count "$dir")\t$dir"
            fi
        done

        echo -e "\n操作用时: $duration 秒"
    } > "$log_file"
}

# 执行备份操作
backup_files() {
    local backup_dest="$1/DockerBackup_$(date +%Y%m%d)"
    mkdir -p "$backup_dest/var/lib/docker" "$backup_dest/etc/docker" "$backup_dest/opt/docker"

    local start_time=$(date +%s)

    echo "开始备份..."
    for dir in /var/lib/docker /etc/docker /opt/docker; do
        if [[ -d "$dir" ]]; then
            rsync_with_progress "$dir/" "$backup_dest${dir}"
        else
            echo "目录 $dir 不存在，跳过..."
        fi
    done

    echo -e "\033[32m备份已完成，备份目的地: $backup_dest\033[0m"

    generate_backup_log "$backup_dest/backup_$(date +%Y%m%d%H%M%S).log" "$start_time" "$backup_dest"
}

# 执行恢复操作
restore_files() {
    local restore_src="$1"
    local start_time=$(date +%s)

    echo "开始恢复..."
    for dir in /var/lib/docker /etc/docker /opt/docker; do
        if [[ -d "$restore_src${dir}" ]]; then
            rsync_with_progress "$restore_src${dir}/" "$dir/"
        else
            echo "目录 $restore_src${dir} 不存在，跳过..."
        fi
    done
    echo "恢复完成。"

    generate_restore_log "$restore_src/restore_$(date +%Y%m%d%H%M%S).log" "$start_time" "$restore_src"
}

main() {
    while true; do
        echo "1) 备份Docker"
        echo "2) 恢复Docker"
        echo "0) 退出"
        read -p "请选择操作：" opt
        case $opt in
            1)
                echo -e "\033[31m注意: 备份目的地建议设置在系统盘以外。\033[0m"
                read -p "请输入备份目的地路径: " backup_dest
                start_rsync
                stop_docker
                backup_files "$backup_dest"
                start_docker
                break
                ;;
            2)
                read -p "请输入恢复文件的路径: " restore_src
                if [[ -d "$restore_src" ]]; then
                    start_rsync
                    stop_docker
                    restore_files "$restore_src"
                    start_docker
                    break
                else
                    echo "输入的恢复文件路径无效，请重新输入。"
                fi
                ;;
            0)
                echo "退出程序。"
                break
                ;;
            *)
                echo "无效选择，请重新输入。"
                ;;
        esac
    done
}

main
