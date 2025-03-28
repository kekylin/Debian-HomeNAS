#!/bin/bash

# ======================= 信号处理 =======================
# 捕获 SIGINT 信号，确保脚本中断时根据原始状态恢复 Docker 服务
trap 'output "INFO" "脚本中断，正在清理..." "" true; if [[ "$docker_was_active" == "active" ]]; then start_docker_service; fi; exit 1' SIGINT

# ======================= 基础工具模块 =======================
# 定义终端颜色常量和工具函数，提供脚本运行的基础支持

declare -A COLORS=(
    ["INFO"]=$'\e[0;36m'    # 青色
    ["SUCCESS"]=$'\e[0;32m' # 绿色
    ["WARNING"]=$'\e[0;33m' # 黄色
    ["ERROR"]=$'\e[0;31m'   # 红色
    ["ACTION"]=$'\e[0;34m'  # 蓝色
    ["WHITE"]=$'\e[1;37m'   # 粗体白色
    ["RESET"]=$'\e[0m'      # 重置颜色
)

# 输出带颜色的消息到终端
output() {
    local type="$1" msg="$2" custom_color="$3" is_log="${4:-false}"
    local color="${custom_color:-${COLORS[$type]:-${COLORS[INFO]}}}"
    local prefix=""
    [[ "$is_log" == "true" ]] && prefix="[${type}] "
    printf "%b%s%b\n" "$color" "${prefix}${msg}" "${COLORS[RESET]}"
}

# 以指定错误消息和退出码终止脚本
exit_with_error() {
    local msg="$1" exit_code="${2:-1}"
    output "ERROR" "$msg" "" true
    exit "$exit_code"
}

# 规范化文件或目录路径
normalize_path() {
    realpath -s "$1" 2>/dev/null || echo "$1"
}

# 检查路径权限
check_path_permissions() {
    local path="$1" actions="$2"
    for action in $actions; do
        case "$action" in
            read) [[ ! -r "$path" ]] && exit_with_error "无读取权限: $path" 1 ;;
            write) [[ ! -w "$path" ]] && exit_with_error "无写入权限: $path" 1 ;;
            *) exit_with_error "未知权限类型: $action" 1 ;;
        esac
    done
}

# 获取目录大小和文件数
get_dir_stats() {
    local dir="$1"
    if [[ -d "$dir" ]]; then
        local size=$(du -s "$dir" 2>/dev/null | awk '{print $1}')
        local count=$(find "$dir" -type f 2>/dev/null | wc -l)
        echo "$size $count"
    else
        echo "0 0"
    fi
}

# 格式化文件大小为可读单位
format_file_size() {
    local size_kb="$1"
    if [[ $size_kb -lt 1024 ]]; then
        echo "${size_kb}KB"
    elif [[ $size_kb -lt $((1024 * 1024)) ]]; then
        echo "$(awk "BEGIN {printf \"%.2f\", $size_kb / 1024}")MB"
    else
        echo "$(awk "BEGIN {printf \"%.2f\", $size_kb / 1024 / 1024}")GB"
    fi
}

# ======================= 服务管理模块 =======================
# 提供 rsync 和 Docker 服务的启动与停止功能

start_rsync_service() {
    output "ACTION" "启动 rsync 服务" "" true
    systemctl start rsync || exit_with_error "无法启动 rsync 服务" 1
}

stop_rsync_service() {
    output "ACTION" "停止 rsync 服务" "" true
    systemctl stop rsync || exit_with_error "无法停止 rsync 服务" 1
}

stop_docker_service() {
    output "ACTION" "停止 Docker 服务" "" true
    systemctl stop docker.service docker.socket || exit_with_error "无法停止 Docker 服务" 1
    timeout 30 bash -c 'while systemctl is-active --quiet docker.service || systemctl is-active --quiet docker.socket; do sleep 1; done' || exit_with_error "无法停止 Docker 服务" 1
    output "SUCCESS" "Docker 服务已停止" "" true
    output "INFO" "Docker 服务已停止，相关服务可能受到影响" "" true
}

start_docker_service() {
    output "ACTION" "启动 Docker 服务" "" true
    systemctl start docker.service docker.socket || exit_with_error "无法启动 Docker 服务" 1
    output "SUCCESS" "Docker 服务已启动" "" true
}

# ======================= 配置加载模块 =======================
# 解析和管理 Docker 备份的配置文件

# 默认配置文件内容
DEFAULT_CONFIG=$(cat << 'EOF'
# docker_backup.conf 配置文件
#
# 此文件用于配置 Docker 备份脚本的行为。
# 请确保配置文件格式正确，否则脚本将无法正常运行。
# 所有路径必须是绝对路径（以 / 开头）。

# BACKUP_DIRS: 需要备份的目录列表，以空格分隔。
# 示例：BACKUP_DIRS="/var/lib/docker /etc/docker /opt/docker"
BACKUP_DIRS="/var/lib/docker /etc/docker /opt/docker"

# BACKUP_DEST: 备份文件存储的根路径。
# 建议设置在系统盘以外的路径，如 /mnt/backup 或 /media/backup。
# 示例：BACKUP_DEST="/mnt/backup"
BACKUP_DEST="/mnt/backup"

# EXCLUDE_DIRS: 在备份时需要排除的目录列表，以空格分隔。
# 示例：EXCLUDE_DIRS="/var/lib/docker/tmp /opt/docker/cache"
EXCLUDE_DIRS=
EOF
)

parse_config_content() {
    local config_content="$1"
    mapfile -t config_entries < <(echo "$config_content" | grep -Ev '^#|^\s*$')
    for line in "${config_entries[@]}"; do
        IFS='=' read -r key value <<< "$line"
        value="${value//[! -~]/}"
        value="${value//\"/}"
        case "$key" in
            BACKUP_DIRS) BACKUP_DIRS="$value" ;;
            BACKUP_DEST) BACKUP_DEST="$value" ;;
            EXCLUDE_DIRS) EXCLUDE_DIRS="$value" ;;
            *) output "WARNING" "未知配置项: $key" "" true ;;
        esac
    done
    [[ -z "$BACKUP_DIRS" ]] && exit_with_error "配置文件缺少 BACKUP_DIRS" 1
    read -r -a SOURCE_DIRS <<< "$BACKUP_DIRS"
    read -r -a EXCLUDED_DIRS <<< "$EXCLUDE_DIRS"
}

load_backup_config() {
    output "WHITE" "请输入 docker_backup.conf 配置文件路径（留空使用默认配置）:" "" false
    read -e -p "" config_path  # 启用路径补全

    if [[ -z "$config_path" ]]; then
        output "INFO" "未提供配置文件，使用默认配置" "" true
        parse_config_content "$DEFAULT_CONFIG"
        while true; do
            output "WHITE" "请输入备份文件存储路径（例如 /mnt/backup）:" "" false
            read -e -p "" backup_dest  # 启用路径补全
            if [[ -n "$backup_dest" && "$backup_dest" =~ ^/ ]]; then
                BACKUP_DEST=$(normalize_path "$backup_dest")
                break
            else
                output "ERROR" "备份路径必须是绝对路径（以 / 开头），请重新输入" "" true
            fi
        done
    else
        local config_file=$(normalize_path "$config_path")
        if [[ ! -f "$config_file" ]]; then
            exit_with_error "配置文件 $config_file 不存在" 1
        fi
        check_path_permissions "$config_file" "read"
        output "INFO" "加载用户提供的配置文件: $config_file" "" true
        parse_config_content "$(cat "$config_file")"
        [[ -z "$BACKUP_DEST" ]] && exit_with_error "配置文件缺少 BACKUP_DEST" 1
    fi

    for dir in "${SOURCE_DIRS[@]}"; do
        [[ ! "$dir" =~ ^/ ]] && exit_with_error "BACKUP_DIRS 中的路径必须是绝对路径: $dir" 1
    done
    [[ ! "$BACKUP_DEST" =~ ^/ ]] && exit_with_error "BACKUP_DEST 必须是绝对路径: $BACKUP_DEST" 1
    for dir in "${EXCLUDED_DIRS[@]}"; do
        [[ -n "$dir" && ! "$dir" =~ ^/ ]] && exit_with_error "EXCLUDE_DIRS 中的路径必须是绝对路径: $dir" 1
    done
}

# ======================= 版本管理模块 =======================
# 获取备份的下一个版本号

get_next_version() {
    local dest_dir="$1" base_name="$2"
    local version=0
    for dir in "$dest_dir/${base_name}_v"*; do
        if [[ -d "$dir" && "$(basename "$dir")" =~ ^${base_name}_v([0-9]+)$ ]]; then
            local v=${BASH_REMATCH[1]}
            ((v > version)) && version=$v
        fi
    done
    echo $((version + 1))
}

# ======================= 日志生成模块 =======================
# 生成操作日志文件，包含备份或恢复的详细信息

generate_operation_log() {
    local log_file="$1" start_time="$2" end_time="$3" type="$4" num_excludes="$5"
    local restore_mode=""
    local offset=5

    if [[ "$type" == "restore" ]]; then
        restore_mode="$6"
        offset=6
    fi

    local -a valid_excludes=("${@:$((offset + 1)):$num_excludes}")
    local exclude_end=$((offset + num_excludes))
    local total_args=$#
    local remaining_args=$((total_args - exclude_end))
    local src_count=$((remaining_args / 2))
    local -a src_dirs=("${@:$((exclude_end + 1)):$src_count}")
    local -a dest_dirs=("${@:$((exclude_end + src_count + 1)):$src_count}")

    local duration=$((end_time - start_time))
    local total_size_kb=0 total_files=0 dest_total_size_kb=0 dest_total_files=0 exclude_total_size_kb=0 exclude_total_files=0
    local src_label dest_label src_file_label dest_file_label time_label

    if [[ "$type" == "backup" ]]; then
        src_label="源目录大小（备份前）"
        dest_label="目标目录大小（备份后）"
        src_file_label="源文件数量（备份前）"
        dest_file_label="目标文件数量（备份后）"
        time_label="备份时间"
    elif [[ "$type" == "restore" ]]; then
        src_label="备份源目录大小（恢复前）"
        dest_label="目标目录大小（恢复后）"
        src_file_label="备份源文件数量（恢复前）"
        dest_file_label="目标文件数量（恢复后）"
        time_label="恢复时间"
    else
        exit_with_error "无效的日志类型: $type" 1
    fi

    mkdir -p "$(dirname "$log_file")" || exit_with_error "无法创建日志目录: $(dirname "$log_file")" 1
    {
        echo "$time_label: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "------------------------------------------"
        if [[ "$type" == "backup" ]]; then
            echo "备份目录列表:"
            for dir in "${src_dirs[@]}"; do
                echo "  ${dir}"
            done
            echo "------------------------------------------"
        fi
        echo "$src_label:"
        for dir in "${src_dirs[@]}"; do
            read -r size count <<< "$(get_dir_stats "$dir")"
            echo "  $(format_file_size "$size")    ${dir}"
            total_size_kb=$((total_size_kb + size))
            total_files=$((total_files + count))
        done
        echo "  总计: $(format_file_size "$total_size_kb")"
        echo ""
        echo "$src_file_label:"
        for dir in "${src_dirs[@]}"; do
            read -r size count <<< "$(get_dir_stats "$dir")"
            echo "  ${count}    ${dir}"
        done
        echo "  总计: $total_files"
        echo "------------------------------------------"
        echo "$dest_label:"
        for dir in "${dest_dirs[@]}"; do
            read -r size count <<< "$(get_dir_stats "$dir")"
            echo "  $(format_file_size "$size")    ${dir}"
            dest_total_size_kb=$((dest_total_size_kb + size))
            dest_total_files=$((dest_total_files + count))
        done
        echo "  总计: $(format_file_size "$dest_total_size_kb")"
        echo ""
        echo "$dest_file_label:"
        for dir in "${dest_dirs[@]}"; do
            read -r size count <<< "$(get_dir_stats "$dir")"
            echo "  ${count}    ${dir}"
        done
        echo "  总计: $dest_total_files"
        echo "------------------------------------------"
        if [[ "$type" == "backup" ]]; then
            echo "排除目录大小:"
            if [[ ${#valid_excludes[@]} -eq 0 ]]; then
                echo "  无"
            else
                for exclude in "${valid_excludes[@]}"; do
                    read -r size count <<< "$(get_dir_stats "$exclude")"
                    echo "  $(format_file_size "$size")    ${exclude}"
                    exclude_total_size_kb=$((exclude_total_size_kb + size))
                    exclude_total_files=$((exclude_total_files + count))
                done
                echo "  总计: $(format_file_size "$exclude_total_size_kb")"
            fi
            echo ""
            echo "排除目录文件数量:"
            if [[ ${#valid_excludes[@]} -eq 0 ]]; then
                echo "  无"
            else
                for exclude in "${valid_excludes[@]}"; do
                    read -r size count <<< "$(get_dir_stats "$exclude")"
                    echo "  ${count}    ${exclude}"
                done
                echo "  总计: $exclude_total_files"
            fi
            echo "------------------------------------------"
        fi
        if [[ "$type" == "restore" && -n "$restore_mode" ]]; then
            if [[ "$restore_mode" == "clear" ]]; then
                echo "恢复模式: 清空恢复"
            elif [[ "$restore_mode" == "incremental" ]]; then
                echo "恢复模式: 增量恢复"
            fi
            echo "------------------------------------------"
        fi
        echo "操作耗时: $duration 秒"
    } > "$log_file"
}

# ======================= 核心功能模块 =======================
# 实现 Docker 文件的备份和恢复功能

backup_files() {
    local base_name="docker_$(date +%Y%m%d)"

    if [[ ! -d "$BACKUP_DEST" ]]; then
        mkdir -p "$BACKUP_DEST" || exit_with_error "无法创建备份目标目录: $BACKUP_DEST" 1
        output "INFO" "备份目标目录不存在，已创建: $BACKUP_DEST" "" true
    fi

    local version=$(get_next_version "$BACKUP_DEST" "$base_name")
    local backup_dest=$(normalize_path "$BACKUP_DEST/${base_name}_v${version}")
    mkdir -p "$backup_dest" || exit_with_error "无法创建备份目录: $backup_dest" 1

    local -a src_dirs=("${SOURCE_DIRS[@]}")
    local start_time=$(date +%s)
    declare -A exclude_map
    for exclude in "${EXCLUDED_DIRS[@]}"; do
        exclude_map["$(normalize_path "$exclude")"]=1
    done

    local -a valid_excludes=()
    for exclude in "${!exclude_map[@]}"; do
        for dir in "${src_dirs[@]}"; do
            if [[ "$exclude" == "$dir"/* && "$exclude" != "$dir" ]]; then
                valid_excludes+=("$exclude")
                output "INFO" "排除目录生效: $exclude" "" true
                break
            fi
        done
    done

    # 启动 rsync 服务（如果原始状态为非活动，则在操作后需停止）
    if [[ "$rsync_was_active" != "active" ]]; then
        start_rsync_service
    fi

    # 停止 Docker 服务（如果原始状态为活动，则在操作后需启动）
    if [[ "$docker_was_active" == "active" ]]; then
        stop_docker_service
    fi

    output "ACTION" "执行备份操作" "" true
    for dir in "${src_dirs[@]}"; do
        dir=$(normalize_path "$dir")
        if [[ -d "$dir" ]]; then
            check_path_permissions "$dir" "read"
            local dest_dir="$backup_dest${dir}"
            mkdir -p "$dest_dir" || exit_with_error "无法创建目标目录: $dest_dir" 1
            local rsync_args=(-a --no-motd --info=progress2 --ignore-missing-args)
            for exclude in "${valid_excludes[@]}"; do
                rsync_args+=(--exclude="${exclude#$dir/}")
            done
            read -r size count <<< "$(get_dir_stats "$dir")"
            output "INFO" "备份目录: $dir (文件数: $count, 总大小: $(format_file_size "$size"))" "" true
            rsync "${rsync_args[@]}" "$dir/" "$dest_dir/" || {
                local exit_code=$?
                rm -rf "$backup_dest"
                exit_with_error "备份目录 $dir 失败，错误码: $exit_code" "$exit_code"
            }
        else
            output "WARNING" "目录 $dir 不存在，已跳过备份" "" true
        fi
    done

    local end_time=$(date +%s)
    local log_file="$backup_dest/backup_$(date +%Y%m%d%H%M%S).log"
    local -a dest_dirs=()
    for dir in "${src_dirs[@]}"; do
        [[ -d "$backup_dest${dir}" ]] && dest_dirs+=("$backup_dest${dir}")
    done

    if [[ ${#src_dirs[@]} -eq 0 ]]; then
        exit_with_error "备份目录列表为空，请检查配置文件 BACKUP_DIRS" 1
    fi

    generate_operation_log "$log_file" "$start_time" "$end_time" "backup" "${#valid_excludes[@]}" "${valid_excludes[@]}" "${src_dirs[@]}" "${dest_dirs[@]}"
    output "SUCCESS" "备份操作完成，目标路径: $backup_dest" "" true

    # 根据原始状态恢复服务
    if [[ "$rsync_was_active" != "active" ]]; then
        stop_rsync_service
    fi
    if [[ "$docker_was_active" == "active" ]]; then
        start_docker_service
    fi
}

restore_files() {
    local restore_src=$(normalize_path "$1")
    local start_time=$(date +%s)

    local dir_name=$(basename "$restore_src")
    [[ ! "$dir_name" =~ ^docker_[0-9]{8}_v[0-9]+$ ]] && exit_with_error "恢复路径格式无效: $restore_src，必须为 docker_YYYYMMDD_vN 格式" 1
    [[ ! -d "$restore_src" ]] && exit_with_error "恢复路径不存在或不是目录: $restore_src" 1
    check_path_permissions "$restore_src" "read"

    local latest_log=$(find "$restore_src" -maxdepth 1 -type f -name "backup_*.log" | sort -r | head -n 1)
    [[ -z "$latest_log" || ! -f "$latest_log" ]] && exit_with_error "未找到备份日志文件: $restore_src" 1

    mapfile -t backup_dirs < <(awk '/备份目录列表:/{flag=1;next} /^---/{flag=0} flag && NF {print $1}' "$latest_log")
    [[ ${#backup_dirs[@]} -eq 0 ]] && exit_with_error "备份日志中未找到有效目录列表" 1

    output "INFO" "可恢复目录列表:" "" true
    for i in "${!backup_dirs[@]}"; do
        output "WHITE" "$((i+1))) ${backup_dirs[$i]}" "" false
    done

    while true; do
        output "WHITE" "请输入需要恢复的目录编号（单选示例: 1，多选示例: 1 2 3，全选输入 0）:" "" false
        read -p "" selection
        if [[ "$selection" =~ ^[0-9\ ]+$ || "$selection" == "0" ]]; then
            break
        else
            output "ERROR" "输入无效，仅允许数字和空格（示例: 1, 1 2 3 或 0），请重新输入" "" true
        fi
    done

    local -a selected_dirs
    if [[ "$selection" == "0" ]]; then
        selected_dirs=("${backup_dirs[@]}")
    else
        read -r -a indices <<< "$selection"
        for index in "${indices[@]}"; do
            if [[ $index -gt 0 && $index -le ${#backup_dirs[@]} ]]; then
                selected_dirs+=("${backup_dirs[$((index-1))]}")
            else
                output "WARNING" "编号 $index 无效，已忽略" "" true
            fi
        done
        [[ ${#selected_dirs[@]} -eq 0 ]] && exit_with_error "未选择有效目录，恢复操作已取消" 1
    fi

    while true; do
        output "WHITE" "请选择恢复模式:" "" false
        output "WHITE" "1) 清空恢复（先清空目标目录再恢复）" "" false
        output "WHITE" "2) 增量恢复（覆盖同名文件，保留目标目录中备份源没有的文件）" "" false
        read -p "" mode
        if [[ "$mode" == "1" ]]; then
            restore_mode="clear"
            break
        elif [[ "$mode" == "2" ]]; then
            restore_mode="incremental"
            break
        else
            output "WARNING" "无效选择，请输入 1 或 2" "" true
        fi
    done

    local confirm_msg="恢复操作将"
    if [[ "$restore_mode" == "clear" ]]; then
        confirm_msg+="清空目标目录并"
    fi
    confirm_msg+="同步备份内容，确认继续？(Y/n):"
    output "WARNING" "$confirm_msg" "" true
    read -p "" confirm
    if [[ ! "$confirm" =~ ^[Yy]$ && -n "$confirm" ]]; then
        output "INFO" "恢复操作已取消" "" true
        exit 0
    fi

    # 启动 rsync 服务（如果原始状态为非活动，则在操作后需停止）
    if [[ "$rsync_was_active" != "active" ]]; then
        start_rsync_service
    fi

    # 停止 Docker 服务（如果原始状态为活动，则在操作后需启动）
    if [[ "$docker_was_active" == "active" ]]; then
        stop_docker_service
    fi

    local -a src_dirs dest_dirs
    for dir in "${selected_dirs[@]}"; do
        src_dirs+=("$restore_src${dir}")
        dest_dirs+=("${dir}")
    done

    output "ACTION" "执行恢复操作" "" true
    for dir in "${selected_dirs[@]}"; do
        local src_dir="$restore_src${dir}"
        local dest_dir=$(normalize_path "$dir")
        if [[ -d "$src_dir" ]]; then
            check_path_permissions "$dest_dir" "write" 2>/dev/null || true
            read -r size count <<< "$(get_dir_stats "$src_dir")"
            output "INFO" "恢复目录: $dest_dir (文件数: $count, 总大小: $(format_file_size "$size"))" "" true
            if [[ "$restore_mode" == "clear" ]]; then
                rm -rf "$dest_dir"/* 2>/dev/null
            fi
            mkdir -p "$dest_dir"
            rsync -a --no-motd --info=progress2 "$src_dir/" "$dest_dir/" || {
                local exit_code=$?
                output "ERROR" "恢复目录 $dest_dir 失败，错误码: $exit_code" "" true
                if [[ "$docker_was_active" == "active" ]]; then start_docker_service; fi
                exit_with_error "恢复失败" "$exit_code"
            }
        else
            output "WARNING" "目录 $src_dir 不存在，已跳过恢复" "" true
        fi
    done

    local end_time=$(date +%s)
    local log_file="$restore_src/restore_$(date +%Y%m%d%H%M%S).log"
    generate_operation_log "$log_file" "$start_time" "$end_time" "restore" 0 "$restore_mode" "${src_dirs[@]}" "${dest_dirs[@]}"
    output "SUCCESS" "恢复操作完成" "" true

    # 根据原始状态恢复服务
    if [[ "$rsync_was_active" != "active" ]]; then
        stop_rsync_service
    fi
    if [[ "$docker_was_active" == "active" ]]; then
        start_docker_service
    fi
}

# ======================= 程序入口模块 =======================
# 主函数，提供用户交互界面并控制备份与恢复流程

main() {
    while true; do
        output "WHITE" "1) 备份 Docker" "" false
        output "WHITE" "2) 恢复 Docker" "" false
        output "WHITE" "0) 退出" "" false
        output "WHITE" "请选择操作:" "" false
        read -p "" option
        case $option in
            1)
                # 检测服务状态
                rsync_was_active=$(systemctl is-active rsync)
                docker_was_active=$(systemctl is-active docker.service)
                load_backup_config
                backup_files
                exit 0
                ;;
            2)
                # 检测服务状态
                rsync_was_active=$(systemctl is-active rsync)
                docker_was_active=$(systemctl is-active docker.service)
                output "WHITE" "请输入恢复文件路径（示例: /path/to/docker_20250323_v1）:" "" false
                read -e -p "" restore_src  # 启用路径补全
                if [[ -d "$restore_src" ]]; then
                    restore_files "$restore_src"
                    exit 0
                else
                    output "ERROR" "恢复文件路径无效，请重新输入" "" true
                fi
                ;;
            0)
                output "INFO" "程序已退出" "" true
                exit 0
                ;;
            *)
                output "WARNING" "选项无效，请重新选择" "" true
                ;;
        esac
    done
}

main "$@"
