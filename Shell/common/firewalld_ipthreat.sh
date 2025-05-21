#!/bin/bash

# 脚本功能：管理 Firewalld 的 IP 封禁，基于威胁等级自动更新或手动操作，支持定时任务。

# ==================== 颜色输出模块 ====================
# 定义输出颜色，用于格式化不同类型的消息
declare -A COLORS=(
    ["INFO"]=$'\e[0;36m'
    ["SUCCESS"]=$'\e[0;32m'
    ["WARNING"]=$'\e[0;33m'
    ["ERROR"]=$'\e[0;31m'
    ["ACTION"]=$'\e[0;34m'
    ["WHITE"]=$'\e[1;37m'
    ["RESET"]=$'\e[0m'
)

output() {
    # 格式化输出消息，带颜色和类型前缀
    local type="${1}" msg="${2}" custom_color="${3}"
    local color="${custom_color:-${COLORS[$type]}}"
    local prefix="[${type}] "
    printf "%b%s%b\n" "${color}" "${prefix}${msg}" "${COLORS[RESET]}"
}

# ==================== 常量定义 ====================
# 配置文件路径
CONFIG_DIR="/etc/firewalld/ipthreat"
CONFIG_FILE="${CONFIG_DIR}/ipthreat.conf"
# 定时脚本文件路径
CRON_SCRIPT_PATH="${CONFIG_DIR}/firewalld_ipthreat.sh"
# 默认威胁等级
DEFAULT_THREAT_LEVEL=50
# 默认更新定时任务（每天 0:00、6:00、12:00、18:00）
DEFAULT_UPDATE_CRON="0 0,6,12,18 * * *"
# 默认清空定时任务（每月1日 01:00）
DEFAULT_CLEANUP_CRON="0 1 1 * *"
# Firewalld 区域
ZONE="drop"
# IPv4 和 IPv6 IPSet 名称
IPSET_NAME_IPV4="ipthreat_block"
IPSET_NAME_IPV6="ipthreat_block_ipv6"
# IP 范围最大值
declare -i MAX_RANGE_SIZE=1000
# IPSet 最大容量
declare -i MAX_IP_LIMIT=65536
# 批处理大小
declare -i BATCH_SIZE=10000
# 手动输入 IP 上限
declare -i MAX_MANUAL_INPUT=1000
# 最小时间间隔（分钟）
declare -i MIN_TIME_GAP=10

# 验证 MAX_IP_LIMIT 是否为有效数字
if ! [[ "$MAX_IP_LIMIT" =~ ^[0-9]+$ ]]; then
    output "ERROR" "MAX_IP_LIMIT 无效：$MAX_IP_LIMIT（需为数字）"
    exit 1
fi

# 确保配置目录存在
if [[ ! -d "$CONFIG_DIR" ]]; then
    output "INFO" "创建目录：$CONFIG_DIR"
    if ! mkdir -p "$CONFIG_DIR"; then
        output "ERROR" "创建目录失败：$CONFIG_DIR（检查权限）"
        exit 1
    fi
    chmod 755 "$CONFIG_DIR"
fi

# 加载配置文件，仅加载指定变量
if [[ -f "$CONFIG_FILE" ]]; then
    source <(grep -E '^(THREAT_LEVEL|UPDATE_CRON|CLEANUP_CRON)=' "$CONFIG_FILE") || {
        output "ERROR" "加载配置文件失败：$CONFIG_FILE（检查格式）"
        exit 1
    }
fi

# ==================== 临时文件管理 ====================
# 创建临时文件用于存储下载数据和处理结果
TEMP_GZ=$(mktemp /tmp/threat.XXXXXX.gz)
TEMP_TXT=$(mktemp /tmp/threat.XXXXXX.txt)
TEMP_IP_LIST_IPV4=$(mktemp /tmp/valid_ips_ipv4.XXXXXX.txt)
TEMP_IP_LIST_IPV6=$(mktemp /tmp/valid_ips_ipv6.XXXXXX.txt)

# 清理临时文件并退出脚本
trap 'rm -f "$TEMP_GZ" "$TEMP_TXT" "$TEMP_IP_LIST_IPV4" "$TEMP_IP_LIST_IPV6"; output "ERROR" "脚本中断，临时文件已清理"; exit 1' INT TERM

# ==================== 时间冲突检测 ====================
check_cron_conflict() {
    # 检查新 Cron 规则与现有规则是否存在时间冲突，输出适当的警告
    local new_cron="$1"
    local existing_cron="$2"
    local task_type="$3"  # 新任务类型：update 或 cleanup
    local existing_task_type="$4"  # 现有任务类型：update 或 cleanup

    # 如果没有现有任务或 existing_cron 无效，直接返回
    if [[ -z "$existing_cron" ]]; then
        return 0
    fi
    # 验证 existing_cron 是否对应实际的 crontab 任务
    local cron_exists=0
    if [[ "$existing_task_type" == "cleanup" ]]; then
        crontab -l 2>/dev/null | grep -q "# IPThreat Firewalld Cleanup" && cron_exists=1
    elif [[ "$existing_task_type" == "update" ]]; then
        crontab -l 2>/dev/null | grep -q "# IPThreat Firewalld Update" && cron_exists=1
    fi
    if [[ $cron_exists -eq 0 ]]; then
        output "INFO" "现有 $existing_task_type 任务（$existing_cron）未在 crontab 中找到，忽略冲突检查"
        return 0
    fi

    local new_parts=($new_cron)
    local existing_parts=($existing_cron)
    local new_min=${new_parts[0]}
    local new_hour=${new_parts[1]}
    local new_day=${new_parts[2]}
    local existing_min=${existing_parts[0]}
    local existing_hour=${existing_parts[1]}
    local existing_day=${existing_parts[2]}

    # 解析分钟字段并验证间隔 >= 60 分钟
    local new_min_value
    if [[ "$new_min" =~ ^\*/([0-9]+)$ ]]; then
        new_min_value=${BASH_REMATCH[1]}
        if ! [[ "$new_min_value" =~ ^[0-9]+$ ]] || [[ "$new_min_value" -lt 60 ]] || [[ "$new_min_value" -gt 59 ]]; then
            output "ERROR" "无效 Cron 分钟间隔：$new_min（需 >= 60 分钟或使用固定时间点）"
            return 1
        fi
    elif [[ "$new_min" =~ ^[0-9]+$ ]] || [[ "$new_min" =~ ^[0-9,]+$ ]]; then
        new_min_value="$new_min"
    else
        output "ERROR" "不支持的 Cron 分钟格式：$new_min（仅支持数字、逗号分隔的数字或 */N，且 N >= 60）"
        return 1
    fi

    # 验证小时和分钟字段，支持 * 和逗号分隔的数字
    if ! [[ "$new_hour" =~ ^[0-9,*]+$ && "$existing_min" =~ ^[0-9]+$ && "$existing_hour" =~ ^[0-9,*]+$ ]]; then
        output "ERROR" "Cron 规则格式无效：new_cron=$new_cron, existing_cron=$existing_cron"
        return 1
    fi

    # 处理小时字段（支持 * 和多值）
    local new_hours=()
    if [[ "$new_hour" == "*" ]]; then
        new_hours=({0..23})
    else
        IFS=',' read -ra new_hours <<< "$new_hour"
    fi
    local existing_hours=()
    if [[ "$existing_hour" == "*" ]]; then
        existing_hours=({0..23})
    else
        IFS=',' read -ra existing_hours <<< "$existing_hour"
    fi

    # 处理分钟字段（支持多值）
    local new_mins=()
    if [[ "$new_min" =~ ^[0-9]+$ ]]; then
        new_mins=("$new_min")
    else
        IFS=',' read -ra new_mins <<< "$new_min"
    fi
    local existing_mins=()
    if [[ "$existing_min" =~ ^[0-9]+$ ]]; then
        existing_mins=("$existing_min")
    else
        IFS=',' read -ra existing_mins <<< "$existing_min"
    fi

    # 检查时间冲突
    local conflict_found=0
    for new_h in "${new_hours[@]}"; do
        for new_m in "${new_mins[@]}"; do
            for existing_h in "${existing_hours[@]}"; do
                for existing_m in "${existing_mins[@]}"; do
                    # 检查是否是合法数字
                    if ! [[ "$new_h" =~ ^[0-9]+$ && "$new_m" =~ ^[0-9]+$ && "$existing_h" =~ ^[0-9]+$ && "$existing_m" =~ ^[0-9]+$ ]]; then
                        output "ERROR" "无效时间值：new_hour=$new_h, new_min=$new_m, existing_hour=$existing_h, existing_min=$existing_m"
                        return 1
                    fi
                    local new_total_min=$((new_h * 60 + new_m))
                    local existing_total_min=$((existing_h * 60 + existing_m))
                    local time_diff=$(( (new_total_min - existing_total_min + 1440) % 1440 ))
                    if [[ $time_diff -lt $MIN_TIME_GAP || $time_diff -gt $((1440 - MIN_TIME_GAP)) ]]; then
                        if [[ "$task_type" == "update" ]]; then
                            output "ERROR" "更新规则 $new_cron 与清空任务（$existing_cron）时间间隔小于 10 分钟，不允许设置"
                        else
                            output "ERROR" "清空规则 $new_cron 与更新任务（$existing_cron）时间间隔小于 10 分钟，不允许设置"
                        fi
                        conflict_found=1
                        break 4
                    fi
                done
            done
        done
    done

    [[ $conflict_found -eq 1 ]] && return 1
    return 0
}

# ==================== IP 地址验证 ====================
valid_ipv4() {
    # 验证 IPv4 地址格式
    local ip=$1
    if [[ $ip =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]]; then
        local a=${BASH_REMATCH[1]} b=${BASH_REMATCH[2]} c=${BASH_REMATCH[3]} d=${BASH_REMATCH[4]}
        [[ $a -le 255 && $b -le 255 && $c -le 255 && $d -le 255 && $a -ge 0 ]]
    else
        return 1
    fi
}

valid_ipv6() {
    # 验证 IPv6 地址格式
    local ip=$1
    if [[ $ip =~ ^([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}$ ]] ||
       [[ $ip =~ ^([0-9a-fA-F]{1,4}:){1,7}:$ ]] ||
       [[ $ip =~ ^:([0-9a-fA-F]{1,4}:){1,7}$ ]] ||
       [[ $ip =~ ^([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}$ ]] ||
       [[ $ip =~ ^([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}$ ]] ||
       [[ $ip =~ ^([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}$ ]] ||
       [[ $ip =~ ^([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}$ ]] ||
       [[ $ip =~ ^([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}$ ]] ||
       [[ $ip =~ ^[0-9a-fA-F]{1,4}:(:[0-9a-fA-F]{1,4}){1,6}$ ]] ||
       [[ $ip =~ ^::([0-9a-fA-F]{1,4}:){0,6}[0-9a-fA-F]{1,4}$ ]] ||
       [[ $ip =~ ^::$ ]]; then
        return 0
    else
        return 1
    fi
}

valid_ip() {
    # 判断 IP 类型（IPv4 或 IPv6）
    local ip=$1
    if valid_ipv4 "$ip"; then
        echo "ipv4"
        return 0
    elif valid_ipv6 "$ip"; then
        echo "ipv6"
        return 0
    else
        return 1
    fi
}

valid_cidr_ipv4() {
    # 验证 IPv4 CIDR 格式
    local input=$1
    local prefix mask
    if [[ $input =~ ^([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})/([0-9]{1,2})$ ]]; then
        prefix=${BASH_REMATCH[1]}
        mask=${BASH_REMATCH[2]}
        if [[ ! $mask =~ ^[0-9]+$ ]] || [[ $mask -gt 32 ]] || [[ $mask -lt 0 ]]; then
            output "WARNING" "无效 IPv4 CIDR 掩码：$input"
            return 1
        fi
        if valid_ipv4 "$prefix"; then
            echo "$prefix $mask"
            return 0
        else
            output "WARNING" "无效 IPv4 CIDR 前缀：$input"
            return 1
        fi
    else
        return 1
    fi
}

valid_cidr_ipv6() {
    # 验证 IPv6 CIDR 格式
    local input=$1
    local prefix mask
    if [[ $input =~ ^([0-9a-fA-F:]+)/([0-9]{1,3})$ ]]; then
        prefix=${BASH_REMATCH[1]}
        mask=${BASH_REMATCH[2]}
        if [[ ! $mask =~ ^[0-9]+$ ]] || [[ $mask -gt 128 ]] || [[ $mask -lt 0 ]]; then
            output "WARNING" "无效 IPv6 CIDR 掩码：$input"
            return 1
        fi
        if valid_ipv6 "$prefix"; then
            echo "$prefix $mask"
            return 0
        else
            output "WARNING" "无效 IPv6 CIDR 前缀：$input"
            return 1
        fi
    else
        return 1
    fi
}

expand_ip_range() {
    # 解析 IP 输入（单 IP、CIDR 或范围），并写入临时文件
    local input=$1 output_file_ipv4=$2 output_file_ipv6=$3
    local start_ip end_ip prefix mask ip_count protocol awk_output result

    [[ -z "$input" ]] && {
        output "WARNING" "空输入，跳过处理"
        return 1
    }

    # 移除注释和多余空格
    local clean_ip=$(echo "$input" | cut -d'#' -f1 | tr -d '[:space:]')
    [[ -z "$clean_ip" ]] && {
        output "WARNING" "无效输入（提取后为空）：$input"
        return 1
    }

    # 处理 IPv4 CIDR
    result=$(valid_cidr_ipv4 "$clean_ip")
    if [[ $? -eq 0 ]]; then
        read -r prefix mask <<< "$result"
        ip_count=$((2 ** (32 - mask)))
        if ! [[ "$ip_count" =~ ^[0-9]+$ ]]; then
            output "ERROR" "计算 CIDR IP 数量失败：$clean_ip"
            return 1
        fi
        if [[ $ip_count -gt $MAX_IP_LIMIT ]]; then
            output "WARNING" "IPv4 CIDR 超出上限：$clean_ip（$ip_count 条）"
            return 1
        fi
        echo "$clean_ip" >> "$output_file_ipv4" || {
            output "ERROR" "写入 IPv4 CIDR 失败：$clean_ip"
            return 1
        }
        output "INFO" "解析 IPv4 CIDR：$clean_ip"
        return 0
    fi

    # 处理 IPv6 CIDR
    result=$(valid_cidr_ipv6 "$clean_ip")
    if [[ $? -eq 0 ]]; then
        read -r prefix mask <<< "$result"
        ip_count=$((2 ** (128 - mask)))
        if ! [[ "$ip_count" =~ ^[0-9]+$ ]]; then
            output "ERROR" "计算 CIDR IP 数量失败：$clean_ip"
            return 1
        fi
        if [[ $ip_count -gt $MAX_IP_LIMIT ]]; then
            output "WARNING" "IPv6 CIDR 超出上限：$clean_ip（$ip_count 条）"
            return 1
        fi
        echo "$clean_ip" >> "$output_file_ipv6" || {
            output "ERROR" "写入 IPv6 CIDR 失败：$clean_ip"
            return 1
        }
        output "INFO" "解析 IPv6 CIDR：$clean_ip"
        return 0
    fi

    # 处理 IPv4 范围
    if [[ $clean_ip =~ ^([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})-([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})$ ]]; then
        start_ip=${BASH_REMATCH[1]}
        end_ip=${BASH_REMATCH[2]}
        if ! valid_ipv4 "$start_ip"; then
            output "WARNING" "无效 IPv4 范围起始：$start_ip"
            return 1
        fi
        if ! valid_ipv4 "$end_ip"; then
            output "WARNING" "无效 IPv4 范围结束：$end_ip"
            return 1
        fi
        IFS='.' read -r a b c d <<< "$start_ip"
        start_num=$(( (a * 16777216) + (b * 65536) + (c * 256) + d ))
        IFS='.' read -r a b c d <<< "$end_ip"
        end_num=$(( (a * 16777216) + (b * 65536) + (c * 256) + d ))
        if [[ $start_num -gt $end_num ]]; then
            output "WARNING" "无效 IPv4 范围：$clean_ip（起始大于结束）"
            return 1
        fi
        ip_count=$((end_num - start_num + 1))
        if ! [[ "$ip_count" =~ ^[0-9]+$ ]]; then
            output "ERROR" "计算 IP 范围数量失败：$clean_ip"
            return 1
        fi
        if [[ $ip_count -gt $MAX_IP_LIMIT ]]; then
            output "WARNING" "IPv4 范围超出上限：$clean_ip（$ip_count 条）"
            return 1
        fi
        if [[ $ip_count -gt $MAX_RANGE_SIZE ]]; then
            output "WARNING" "IPv4 范围过大：$clean_ip（建议使用 CIDR）"
            return 1
        fi
        awk_output=$(awk -v start="$start_num" -v end="$end_num" \
            'BEGIN { for (i=start; i<=end; i++) { a=int(i/16777216); b=int((i%16777216)/65536); c=int((i%65536)/256); d=i%256; printf "%d.%d.%d.%d\n", a, b, c, d } }' 2>&1)
        if [[ $? -ne 0 ]]; then
            output "ERROR" "解析 IPv4 范围失败：$clean_ip"
            return 1
        fi
        echo "$awk_output" >> "$output_file_ipv4" || {
            output "ERROR" "写入 IPv4 范围失败：$clean_ip"
            return 1
        }
        output "INFO" "解析 IPv4 范围：$clean_ip"
        return 0
    # 处理 IPv6 范围
    elif [[ $clean_ip =~ ^([0-9a-fA-F:]+)-([0-9a-fA-F:]+)$ ]]; then
        start_ip=${BASH_REMATCH[1]}
        end_ip=${BASH_REMATCH[2]}
        if ! valid_ipv6 "$start_ip" || ! valid_ipv6 "$end_ip"; then
            output "WARNING" "无效 IPv6 范围：$clean_ip"
            return 1
        fi
        echo "$start_ip" >> "$output_file_ipv6" || {
            output "ERROR" "写入 IPv6 范围起始失败：$start_ip"
            return 1
        }
        echo "$end_ip" >> "$output_file_ipv6" || {
            output "ERROR" "写入 IPv6 范围结束失败：$end_ip"
            return 1
        }
        output "INFO" "解析 IPv6 范围：$clean_ip"
        return 0
    fi

    # 处理单 IP
    protocol=$(valid_ip "$clean_ip")
    if [[ $? -eq 0 ]]; then
        if [[ $protocol == "ipv4" ]]; then
            echo "$clean_ip" >> "$output_file_ipv4" || {
                output "ERROR" "写入 IPv4 IP 失败：$clean_ip"
                return 1
            }
            output "INFO" "解析 IPv4 IP：$clean_ip"
        else
            echo "$clean_ip" >> "$output_file_ipv6" || {
                output "ERROR" "写入 IPv6 IP 失败：$clean_ip"
                return 1
            }
            output "INFO" "解析 IPv6 IP：$clean_ip"
        fi
        return 0
    fi

    output "WARNING" "无效输入：$input"
    return 1
}

# ==================== 公共函数 ====================
check_dependencies() {
    # 检查所需命令和服务的可用性
    local missing=0
    for cmd in firewall-cmd wget gzip awk sed grep sort comm split head crontab; do
        if ! command -v "$cmd" &>/dev/null; then
            output "ERROR" "缺少依赖：$cmd（请安装）"
            missing=1
        fi
    done
    if ! systemctl is-active firewalld &>/dev/null; then
        output "ERROR" "Firewalld 未运行（运行 systemctl start firewalld）"
        missing=1
    fi
    if ! systemctl is-active cron &>/dev/null; then
        output "ERROR" "Cron 未运行（运行 systemctl start cron）"
        missing=1
    fi
    [[ $missing -eq 1 ]] && exit 1
}

setup_ipset() {
    # 配置 IPv4 和 IPv6 IPSet，并绑定到指定区域
    if ! firewall-cmd --permanent --get-ipsets | grep -qw "$IPSET_NAME_IPV4"; then
        output "INFO" "创建 IPv4 IPSet：$IPSET_NAME_IPV4"
        if ! firewall-cmd --permanent --new-ipset="$IPSET_NAME_IPV4" --type=hash:ip --option=family=inet --option=maxelem=$MAX_IP_LIMIT &>/dev/null; then
            output "ERROR" "创建 IPv4 IPSet 失败（检查 Firewalld 配置）"
            exit 1
        fi
    fi
    if ! firewall-cmd --permanent --zone="$ZONE" --list-sources | grep -qw "ipset:$IPSET_NAME_IPV4"; then
        output "INFO" "绑定 IPv4 IPSet 到区域：$ZONE"
        if ! firewall-cmd --permanent --zone="$ZONE" --add-source="ipset:$IPSET_NAME_IPV4" &>/dev/null; then
            output "ERROR" "绑定 IPv4 IPSet 失败"
            exit 1
        fi
    fi

    if ! firewall-cmd --permanent --get-ipsets | grep -qw "$IPSET_NAME_IPV6"; then
        output "INFO" "创建 IPv6 IPSet：$IPSET_NAME_IPV6"
        if ! firewall-cmd --permanent --new-ipset="$IPSET_NAME_IPV6" --type=hash:ip --option=family=inet6 --option=maxelem=$MAX_IP_LIMIT &>/dev/null; then
            output "ERROR" "创建 IPv6 IPSet 失败（检查 Firewalld 配置）"
            exit 1
        fi
    fi
    if ! firewall-cmd --permanent --zone="$ZONE" --list-sources | grep -qw "ipset:$IPSET_NAME_IPV6"; then
        output "INFO" "绑定 IPv6 IPSet 到区域：$ZONE"
        if ! firewall-cmd --permanent --zone="$ZONE" --add-source="ipset:$IPSET_NAME_IPV6" &>/dev/null; then
            output "ERROR" "绑定 IPv6 IPSet 失败"
            exit 1
        fi
    fi
}

select_zone() {
    # 验证 Firewalld 区域是否存在
    if ! firewall-cmd --get-zones | grep -qw "$ZONE"; then
        output "ERROR" "无效区域：$ZONE"
        exit 1
    fi
}

get_ipset_usage() {
    # 获取 IPv4 和 IPv6 IPSet 的使用量
    local ipv4_count=0 ipv6_count=0 ipv4_remaining ipv6_remaining
    if firewall-cmd --permanent --get-ipsets | grep -qw "$IPSET_NAME_IPV4"; then
        ipv4_count=$(firewall-cmd --permanent --ipset="$IPSET_NAME_IPV4" --get-entries | wc -l)
        if ! [[ "$ipv4_count" =~ ^[0-9]+$ ]]; then
            output "ERROR" "获取 IPv4 IPSet 计数失败：$ipv4_count"
            exit 1
        fi
        ipv4_remaining=$((MAX_IP_LIMIT - ipv4_count))
        ipv4_status="IPv4: $ipv4_count/$MAX_IP_LIMIT, 剩余: $ipv4_remaining"
    else
        ipv4_status="IPv4: 未配置"
    fi
    if firewall-cmd --permanent --get-ipsets | grep -qw "$IPSET_NAME_IPV6"; then
        ipv6_count=$(firewall-cmd --permanent --ipset="$IPSET_NAME_IPV6" --get-entries | wc -l)
        if ! [[ "$ipv6_count" =~ ^[0-9]+$ ]]; then
            output "ERROR" "获取 IPv6 IPSet 计数失败：$ipv6_count"
            exit 1
        fi
        ipv6_remaining=$((MAX_IP_LIMIT - ipv6_count))
        ipv6_status="IPv6: $ipv6_count/$MAX_IP_LIMIT, 剩余: $ipv6_remaining"
    else
        ipv6_status="IPv6: 未配置"
    fi
    echo "$ipv4_status, $ipv6_status"
}

download_ipthreat_list() {
    # 下载指定威胁等级的 IP 列表
    output "INFO" "下载威胁等级 ${THREAT_LEVEL} IP 列表"
    if ! wget -q "$IPTHREAT_URL" -O "$TEMP_GZ"; then
        output "ERROR" "下载威胁等级 ${THREAT_LEVEL} IP 列表失败"
        return 1
    fi
    if ! gzip -dc "$TEMP_GZ" > "$TEMP_TXT"; then
        output "ERROR" "解压威胁等级 ${THREAT_LEVEL} IP 列表失败"
        rm -f "$TEMP_GZ"
        return 1
    fi
    rm -f "$TEMP_GZ"
    output "SUCCESS" "威胁等级 ${THREAT_LEVEL} IP 列表下载完成"
}

process_ip_list() {
    # 处理 IP 列表，添加或移除 IP，支持批量操作
    local input_file="$1" output_file_ipv4="$2" output_file_ipv6="$3" mode="$4"
    local temp_file_ipv4 temp_file_ipv6 existing_ips_file_ipv4 existing_ips_file_ipv6
    local ipv4_count ipv6_count current_ipv4_count current_ipv6_count
    local ipv4_remaining ipv6_remaining ipv4_to_add ipv6_to_add ipv4_skipped ipv6_skipped
    local input_ipv4_count input_ipv6_count

    temp_file_ipv4=$(mktemp /tmp/expanded_ips_ipv4.XXXXXX.txt)
    temp_file_ipv6=$(mktemp /tmp/expanded_ips_ipv6.XXXXXX.txt)
    existing_ips_file_ipv4=$(mktemp /tmp/existing_ips_ipv4.XXXXXX.txt)
    existing_ips_file_ipv6=$(mktemp /tmp/existing_ips_ipv6.XXXXXX.txt)
    : > "$temp_file_ipv4"
    : > "$temp_file_ipv6"

    # 预处理输入文件，移除空行和注释
    local temp_input=$(mktemp /tmp/processed_input.XXXXXX.txt)
    grep -v '^\s*$' "$input_file" | grep -v '^\s*#' > "$temp_input" || {
        output "WARNING" "输入文件为空或仅含注释"
        rm -f "$temp_input" "$temp_file_ipv4" "$temp_file_ipv6" "$existing_ips_file_ipv4" "$existing_ips_file_ipv6"
        return 1
    }

    # 解析 IP 输入
    local invalid_count=0
    while IFS= read -r ip; do
        [[ -z "$ip" ]] && continue
        if ! expand_ip_range "$ip" "$temp_file_ipv4" "$temp_file_ipv6"; then
            ((invalid_count++))
        fi
    done < "$temp_input"

    rm -f "$temp_input"

    if [[ $invalid_count -gt 0 ]]; then
        output "WARNING" "跳过 $invalid_count 条无效 IP"
    fi

    # 验证临时文件内容
    if [[ ! -s "$temp_file_ipv4" && ! -s "$temp_file_ipv6" ]]; then
        output "ERROR" "无有效 IP（检查输入格式）"
        rm -f "$temp_file_ipv4" "$temp_file_ipv6" "$existing_ips_file_ipv4" "$existing_ips_file_ipv6"
        return 1
    fi

    # 获取现有 IPSet 内容
    if firewall-cmd --permanent --get-ipsets | grep -qw "$IPSET_NAME_IPV4"; then
        firewall-cmd --permanent --ipset="$IPSET_NAME_IPV4" --get-entries | sort > "$existing_ips_file_ipv4" 2>/dev/null
    else
        : > "$existing_ips_file_ipv4"
    fi
    if firewall-cmd --permanent --get-ipsets | grep -qw "$IPSET_NAME_IPV6"; then
        firewall-cmd --permanent --ipset="$IPSET_NAME_IPV6" --get-entries | sort > "$existing_ips_file_ipv6" 2>/dev/null
    else
        : > "$existing_ips_file_ipv6"
    fi
    wait

    # 去重输入 IP
    if ! sort -u "$temp_file_ipv4" > "$output_file_ipv4" 2>/dev/null; then
        output "ERROR" "IPv4 IP 去重失败"
        rm -f "$temp_file_ipv4" "$temp_file_ipv6" "$existing_ips_file_ipv4" "$existing_ips_file_ipv6"
        return 1
    fi
    if ! sort -u "$temp_file_ipv6" > "$output_file_ipv6" 2>/dev/null; then
        output "ERROR" "IPv6 IP 去重失败"
        rm -f "$temp_file_ipv4" "$temp_file_ipv6" "$existing_ips_file_ipv4" "$existing_ips_file_ipv6"
        return 1
    fi

    # 计算输入 IP 数量
    input_ipv4_count=$(wc -l < "$output_file_ipv4")
    input_ipv6_count=$(wc -l < "$output_file_ipv6")
    if ! [[ "$input_ipv4_count" =~ ^[0-9]+$ && "$input_ipv6_count" =~ ^[0-9]+$ ]]; then
        output "ERROR" "计算输入 IP 数量失败：IPv4=$input_ipv4_count, IPv6=$input_ipv6_count"
        return 1
    fi
    output "DEBUG" "输入 IP 数量：IPv4=$input_ipv4_count, IPv6=$input_ipv6_count"

    # 筛选需要添加或移除的 IP
    local new_output_ipv4=$(mktemp /tmp/new_output_ipv4.XXXXXX.txt)
    local new_output_ipv6=$(mktemp /tmp/new_output_ipv6.XXXXXX.txt)
    if [[ "$mode" == "add" ]]; then
        if ! comm -23 "$output_file_ipv4" "$existing_ips_file_ipv4" > "$new_output_ipv4" 2>/dev/null; then
            output "ERROR" "IPv4 IP 比较失败"
            rm -f "$temp_file_ipv4" "$temp_file_ipv6" "$existing_ips_file_ipv4" "$existing_ips_file_ipv6" "$new_output_ipv4" "$new_output_ipv6"
            return 1
        fi
        if ! comm -23 "$output_file_ipv6" "$existing_ips_file_ipv6" > "$new_output_ipv6" 2>/dev/null; then
            output "ERROR" "IPv6 IP 比较失败"
            rm -f "$temp_file_ipv4" "$temp_file_ipv6" "$existing_ips_file_ipv4" "$existing_ips_file_ipv6" "$new_output_ipv4" "$new_output_ipv6"
            return 1
        fi
    elif [[ "$mode" == "remove" ]]; then
        if ! comm -12 "$output_file_ipv4" "$existing_ips_file_ipv4" > "$new_output_ipv4" 2>/dev/null; then
            output "ERROR" "IPv4 IP 比较失败"
            rm -f "$temp_file_ipv4" "$temp_file_ipv6" "$existing_ips_file_ipv4" "$existing_ips_file_ipv6" "$new_output_ipv4" "$new_output_ipv6"
            return 1
        fi
        if ! comm -12 "$output_file_ipv6" "$existing_ips_file_ipv6" > "$new_output_ipv6" 2>/dev/null; then
            output "ERROR" "IPv6 IP 比较失败"
            rm -f "$temp_file_ipv4" "$temp_file_ipv6" "$existing_ips_file_ipv4" "$existing_ips_file_ipv6" "$new_output_ipv4" "$new_output_ipv6"
            return 1
        fi
    fi

    mv "$new_output_ipv4" "$output_file_ipv4" || {
        output "ERROR" "移动 IPv4 输出文件失败：$new_output_ipv4"
        rm -f "$temp_file_ipv4" "$temp_file_ipv6" "$existing_ips_file_ipv4" "$existing_ips_file_ipv6" "$new_output_ipv4" "$new_output_ipv6"
        return 1
    }
    mv "$new_output_ipv6" "$output_file_ipv6" || {
        output "ERROR" "移动 IPv6 输出文件失败：$new_output_ipv6"
        rm -f "$temp_file_ipv4" "$temp_file_ipv6" "$existing_ips_file_ipv4" "$existing_ips_file_ipv6" "$new_output_ipv4" "$new_output_ipv6"
        return 1
    }
    rm -f "$temp_file_ipv4" "$temp_file_ipv6" "$existing_ips_file_ipv4" "$existing_ips_file_ipv6"

    # 调试：检查筛选后的 IP 数量
    ipv4_count=$(wc -l < "$output_file_ipv4")
    ipv6_count=$(wc -l < "$output_file_ipv6")
    if ! [[ "$ipv4_count" =~ ^[0-9]+$ && "$ipv6_count" =~ ^[0-9]+$ ]]; then
        output "ERROR" "计算处理 IP 数量失败：IPv4=$ipv4_count, IPv6=$ipv6_count"
        return 1
    fi
    output "DEBUG" "筛选后 IP 数量：IPv4=$ipv4_count, IPv6=$ipv6_count"

    # 获取当前 IPSet 计数
    if firewall-cmd --permanent --get-ipsets | grep -qw "$IPSET_NAME_IPV4"; then
        current_ipv4_count=$(firewall-cmd --permanent --ipset="$IPSET_NAME_IPV4" --get-entries | wc -l)
        if ! [[ "$current_ipv4_count" =~ ^[0-9]+$ ]]; then
            output "ERROR" "获取 IPv4 IPSet 计数失败：$current_ipv4_count"
            return 1
        fi
    else
        current_ipv4_count=0
    fi
    if firewall-cmd --permanent --get-ipsets | grep -qw "$IPSET_NAME_IPV6"; then
        current_ipv6_count=$(firewall-cmd --permanent --ipset="$IPSET_NAME_IPV6" --get-entries | wc -l)
        if ! [[ "$current_ipv6_count" =~ ^[0-9]+$ ]]; then
            output "ERROR" "获取 IPv6 IPSet 计数失败：$current_ipv6_count"
            return 1
        fi
    else
        current_ipv6_count=0
    fi

    # 处理添加模式下的 IP 限制
    if [[ "$mode" == "add" ]]; then
        ipv4_remaining=$((MAX_IP_LIMIT - current_ipv4_count))
        ipv6_remaining=$((MAX_IP_LIMIT - current_ipv6_count))
        if ! [[ "$ipv4_remaining" =~ ^[0-9]+$ && "$ipv6_remaining" =~ ^[0-9]+$ ]]; then
            output "ERROR" "计算剩余 IP 数量失败：IPv4=$ipv4_remaining, IPv6=$ipv6_remaining"
            return 1
        fi
        ipv4_to_add=$ipv4_count
        ipv6_to_add=$ipv6_count
        ipv4_skipped=0
        ipv6_skipped=0

        if [[ $ipv4_to_add -gt $ipv4_remaining ]]; then
            ipv4_skipped=$((ipv4_to_add - ipv4_remaining))
            ipv4_to_add=$ipv4_remaining
            head -n "$ipv4_to_add" "$output_file_ipv4" > "${output_file_ipv4}.tmp" && mv "${output_file_ipv4}.tmp" "$output_file_ipv4"
        fi
        if [[ $ipv6_to_add -gt $ipv6_remaining ]]; then
            ipv6_skipped=$((ipv6_to_add - ipv6_remaining))
            ipv6_to_add=$ipv6_remaining
            head -n "$ipv6_to_add" "$output_file_ipv6" > "${output_file_ipv6}.tmp" && mv "${output_file_ipv6}.tmp" "$output_file_ipv6"
        fi
    fi

    # 输出处理结果
    if [[ "$mode" == "add" ]]; then
        if [[ $input_ipv4_count -eq 0 && $input_ipv6_count -eq 0 ]]; then
            output "INFO" "无有效 IP 输入"
        elif [[ $ipv4_to_add -eq 0 && $ipv6_to_add -eq 0 ]]; then
            if [[ $input_ipv4_count -gt 0 || $input_ipv6_count -gt 0 ]]; then
                output "INFO" "输入 IP 已存在，无需重复添加"
            fi
        else
            if [[ $ipv4_skipped -gt 0 || $ipv6_skipped -gt 0 ]]; then
                output "WARNING" "超出上限 $MAX_IP_LIMIT，跳过 IPv4: $ipv4_skipped 条，IPv6: $ipv6_skipped 条"
            fi
        fi
    elif [[ "$mode" == "remove" ]]; then
        if [[ $input_ipv4_count -eq 0 && $input_ipv6_count -eq 0 ]]; then
            output "INFO" "无有效 IP 输入"
        elif [[ $ipv4_count -eq 0 && $ipv6_count -eq 0 ]]; then
            output "INFO" "输入 IP 未在封禁列表中"
        fi
    fi

    # 应用 IP 变更
    if [[ $ipv4_count -eq 0 && $ipv6_count -eq 0 ]]; then
        output "INFO" "无 IP 需要处理"
    else
        apply_ip_changes "$output_file_ipv4" "$IPSET_NAME_IPV4" "ipv4" "$mode" &
        apply_ip_changes "$output_file_ipv6" "$IPSET_NAME_IPV6" "ipv6" "$mode" &
        wait
        if [[ "$mode" == "add" ]]; then
            output "SUCCESS" "已封禁 IPv4 IP: $ipv4_to_add 条, IPv6 IP: $ipv6_to_add 条"
        else
            output "SUCCESS" "已解除 IPv4 IP: $ipv4_count 条, IPv6 IP: $ipv6_count 条"
        fi
    fi
}

apply_ip_changes() {
    # 批量应用 IP 变更到 IPSet
    local ip_file=$1 ipset_name=$2 protocol=$3 mode=$4
    local total_ips batch_file batch_count batch_index current_count remaining batch_size

    total_ips=$(wc -l < "$ip_file")
    if ! [[ "$total_ips" =~ ^[0-9]+$ ]]; then
        output "ERROR" "计算总 IP 数量失败：$total_ips"
        return 1
    fi
    if [[ $total_ips -eq 0 ]]; then
        return
    fi

    batch_file=$(mktemp /tmp/batch_ips.XXXXXX.txt)
    if ! firewall-cmd --permanent --get-ipsets | grep -qw "$ipset_name"; then
        output "ERROR" "IPSet 不存在：$ipset_name"
        rm -f "$batch_file"
        return 1
    fi
    current_count=$(firewall-cmd --permanent --ipset="$ipset_name" --get-entries | wc -l)
    if ! [[ "$current_count" =~ ^[0-9]+$ ]]; then
        output "ERROR" "获取 IPSet 计数失败：$current_count"
        rm -f "$batch_file"
        return 1
    fi
    remaining=$((MAX_IP_LIMIT - current_count))
    if ! [[ "$remaining" =~ ^[0-9]+$ ]]; then
        output "ERROR" "计算剩余 IP 数量失败：$remaining"
        rm -f "$batch_file"
        return 1
    fi
    split -l "$BATCH_SIZE" "$ip_file" "$batch_file." --additional-suffix=.txt
    batch_count=$(ls "$batch_file."*.txt | wc -l 2>/dev/null || 0)
    if ! [[ "$batch_count" =~ ^[0-9]+$ ]]; then
        output "ERROR" "计算批次数量失败：$batch_count"
        rm -f "$batch_file."*.txt
        return 1
    fi

    if [[ $batch_count -eq 0 ]]; then
        output "ERROR" "无法创建批次文件（检查磁盘空间或权限）"
        rm -f "$batch_file."*.txt
        return 1
    fi

    output "INFO" "处理 $protocol IP 批次：$batch_count 批"
    for batch in "$batch_file."*.txt; do
        if [[ ! -f "$batch" ]]; then
            output "WARNING" "批次文件不存在：$batch"
            continue
        fi
        batch_size=$(wc -l < "$batch")
        if ! [[ "$batch_size" =~ ^[0-9]+$ ]]; then
            output "ERROR" "计算批次大小失败：$batch_size"
            rm -f "$batch_file."*.txt
            return 1
        fi
        if [[ "$mode" == "add" && $batch_size -gt $remaining ]]; then
            batch_size=$remaining
            head -n "$batch_size" "$batch" > "${batch}.tmp" && mv "${batch}.tmp" "$batch"
            output "WARNING" "批次调整为 $batch_size 条 $protocol IP"
        fi
        if [[ $batch_size -eq 0 ]]; then
            rm -f "$batch"
            continue
        fi
        local cmd_output
        if [[ "$mode" == "add" ]]; then
            cmd_output=$(firewall-cmd --permanent --ipset="$ipset_name" --add-entries-from-file="$batch" 2>&1)
            if [[ $? -ne 0 ]]; then
                if [[ $cmd_output =~ "ipset is full" ]]; then
                    output "ERROR" "IPSet 已满：$ipset_name"
                else
                    output "ERROR" "封禁 $protocol IP 失败：$cmd_output"
                fi
                rm -f "$batch_file."*.txt
                return 1
            fi
        elif [[ "$mode" == "remove" ]]; then
            cmd_output=$(firewall-cmd --permanent --ipset="$ipset_name" --remove-entries-from-file="$batch" 2>&1)
            if [[ $? -ne 0 ]]; then
                output "ERROR" "解除 $protocol IP 失败：$cmd_output"
                rm -f "$batch_file."*.txt
                return 1
            fi
        fi
        remaining=$((remaining - batch_size))
        if ! [[ "$remaining" =~ ^[0-9]+$ ]]; then
            output "ERROR" "更新剩余 IP 数量失败：$remaining"
            rm -f "$batch_file."*.txt
            return 1
        fi
        ((batch_index++))
        rm -f "$batch"
    done

    cmd_output=$(firewall-cmd --reload 2>&1)
    if [[ $? -ne 0 ]]; then
        output "ERROR" "Firewalld 规则重载失败：$cmd_output"
        rm -f "$batch_file."*.txt
        return 1
    fi

    rm -f "$batch_file."*.txt
}

filter_and_add_ips() {
    # 过滤并添加下载的 IP 列表到 IPSet
    [[ ! -f "$TEMP_TXT" ]] && {
        output "ERROR" "IP 列表文件不存在"
        return 1
    }
    setup_ipset
    process_ip_list "$TEMP_TXT" "$TEMP_IP_LIST_IPV4" "$TEMP_IP_LIST_IPV6" "add"
}

manual_add_ips() {
    # 手动添加 IP 到封禁列表
    output "ACTION" "输入封禁 IP（每行一个，单 IP/CIDR/范围，最多 $MAX_MANUAL_INPUT 条，空行结束，Ctrl+C 取消）："
    setup_ipset
    : > "$TEMP_IP_LIST_IPV4"
    : > "$TEMP_IP_LIST_IPV6"
    local temp_input=$(mktemp /tmp/manual_ips.XXXXXX.txt)
    local line_count=0

    while IFS= read -r ip; do
        if [[ -z "$ip" ]]; then
            break
        fi
        if [[ $line_count -ge $MAX_MANUAL_INPUT ]]; then
            output "ERROR" "输入超出上限：$MAX_MANUAL_INPUT 条"
            rm -f "$temp_input"
            return 1
        fi
        echo "$ip" >> "$temp_input"
        ((line_count++))
    done

    if [[ ! -s "$temp_input" ]]; then
        output "ERROR" "无 IP 输入"
        rm -f "$temp_input"
        return 1
    fi

    process_ip_list "$temp_input" "$TEMP_IP_LIST_IPV4" "$TEMP_IP_LIST_IPV6" "add"
    rm -f "$temp_input"
}

manual_remove_ips() {
    # 手动移除 IP 从封禁列表
    if ! firewall-cmd --permanent --get-ipsets | grep -qw "$IPSET_NAME_IPV4" && ! firewall-cmd --permanent --get-ipsets | grep -qw "$IPSET_NAME_IPV6"; then
        output "INFO" "无封禁 IP 或 IPSet 未配置"
        return
    fi
    output "ACTION" "输入解除封禁 IP（每行一个，单 IP/CIDR/范围，最多 $MAX_MANUAL_INPUT 条，空行结束，Ctrl+C 取消）："
    : > "$TEMP_IP_LIST_IPV4"
    : > "$TEMP_IP_LIST_IPV6"
    local temp_input=$(mktemp /tmp/manual_ips.XXXXXX.txt)
    local line_count=0

    while IFS= read -r ip; do
        if [[ -z "$ip" ]]; then
            break
        fi
        if [[ $line_count -ge $MAX_MANUAL_INPUT ]]; then
            output "ERROR" "输入超出上限：$MAX_MANUAL_INPUT 条"
            rm -f "$temp_input"
            return 1
        fi
        echo "$ip" >> "$temp_input"
        ((line_count++))
    done

    if [[ ! -s "$temp_input" ]]; then
        output "ERROR" "无 IP 输入"
        rm -f "$temp_input"
        return 1
    fi

    process_ip_list "$temp_input" "$TEMP_IP_LIST_IPV4" "$TEMP_IP_LIST_IPV6" "remove"
    rm -f "$temp_input"
}

remove_all_ips() {
    # 清空所有封禁 IP 和相关配置
    local sources_ipv4 sources_ipv6 drop_xml_file="/etc/firewalld/zones/drop.xml"
    local ipset_bound_ipv4 ipset_bound_ipv6 drop_has_other_configs

    if ! firewall-cmd --permanent --get-ipsets | grep -qw "$IPSET_NAME_IPV4" && ! firewall-cmd --permanent --get-ipsets | grep -qw "$IPSET_NAME_IPV6"; then
        output "INFO" "无封禁 IP 或 IPSet 未配置"
        return
    fi

    sources_ipv4=$(firewall-cmd --permanent --ipset="$IPSET_NAME_IPV4" --get-entries 2>/dev/null)
    sources_ipv6=$(firewall-cmd --permanent --ipset="$IPSET_NAME_IPV6" --get-entries 2>/dev/null)

    if [[ -z "$sources_ipv4" && -z "$sources_ipv6" ]]; then
        output "INFO" "无封禁 IP"
    else
        if [[ -n "$sources_ipv4" ]]; then
            echo "$sources_ipv4" | tr ' ' '\n' > "$TEMP_IP_LIST_IPV4"
            apply_ip_changes "$TEMP_IP_LIST_IPV4" "$IPSET_NAME_IPV4" "ipv4" "remove"
        fi
        if [[ -n "$sources_ipv6" ]]; then
            echo "$sources_ipv6" | tr ' ' '\n' > "$TEMP_IP_LIST_IPV6"
            apply_ip_changes "$TEMP_IP_LIST_IPV6" "$IPSET_NAME_IPV6" "ipv6" "remove"
        fi
    fi

    ipset_bound_ipv4=$(firewall-cmd --permanent --zone=drop --list-sources | grep -w "ipset:$IPSET_NAME_IPV4" || true)
    ipset_bound_ipv6=$(firewall-cmd --permanent --zone=drop --list-sources | grep -w "ipset:$IPSET_NAME_IPV6" || true)

    if [[ -n "$ipset_bound_ipv4" ]]; then
        output "INFO" "移除 IPv4 IPSet 绑定：$IPSET_NAME_IPV4"
        if ! firewall-cmd --permanent --zone=drop --remove-source="ipset:$IPSET_NAME_IPV4" &>/dev/null; then
            output "ERROR" "移除 IPv4 IPSet 绑定失败"
            return 1
        fi
    fi
    if [[ -n "$ipset_bound_ipv6" ]]; then
        output "INFO" "移除 IPv6 IPSet 绑定：$IPSET_NAME_IPV6"
        if ! firewall-cmd --permanent --zone=drop --remove-source="ipset:$IPSET_NAME_IPV6" &>/dev/null; then
            output "ERROR" "移除 IPv6 IPSet 绑定失败"
            return 1
        fi
    fi

    if firewall-cmd --permanent --get-ipsets | grep -qw "$IPSET_NAME_IPV4"; then
        output "INFO" "删除 IPv4 IPSet：$IPSET_NAME_IPV4"
        if ! firewall-cmd --permanent --delete-ipset="$IPSET_NAME_IPV4" &>/dev/null; then
            output "ERROR" "删除 IPv4 IPSet 失败"
            return 1
        fi
    fi
    if firewall-cmd --permanent --get-ipsets | grep -qw "$IPSET_NAME_IPV6"; then
        output "INFO" "删除 IPv6 IPSet：$IPSET_NAME_IPV6"
        if ! firewall-cmd --permanent --delete-ipset="$IPSET_NAME_IPV6" &>/dev/null; then
            output "ERROR" "删除 IPv6 IPSet 失败"
            return 1
        fi
    fi

    drop_has_other_configs=$(firewall-cmd --permanent --zone=drop --list-all | grep -E "services:|ports:|protocols:|masquerade:|forward-ports:|source-ports:|icmp-blocks:|rich rules:" | grep -v "sources: $" || true)
    if [[ -z "$drop_has_other_configs" ]]; then
        if [[ -f "$drop_xml_file" ]]; then
            output "INFO" "删除 drop 区域配置：$drop_xml_file"
            if ! rm -f "$drop_xml_file"; then
                output "ERROR" "删除 drop 区域配置失败：$drop_xml_file"
                return 1
            fi
        fi
    fi

    if ! firewall-cmd --reload &>/dev/null; then
        output "ERROR" "Firewalld 规则重载失败"
        return 1
    fi

    output "SUCCESS" "已清空所有封禁 IP"
}

enable_auto_update() {
    # 启用定时更新 IP 封禁列表
    local temp_cron cron_schedule input_level
    output "INFO" "威胁等级：0~100，数值越高，IP 危险性越高，数量越少"
    output "ACTION" "输入威胁等级（0~100，默认 50）："
    read -r input_level
    if [[ -z "$input_level" ]]; then
        THREAT_LEVEL=50
        output "INFO" "使用默认威胁等级：50"
    elif [[ ! $input_level =~ ^[0-9]+$ ]] || [[ $input_level -lt 0 ]] || [[ $input_level -gt 100 ]]; then
        output "ERROR" "无效威胁等级：$input_level（需 0~100）"
        return 1
    else
        THREAT_LEVEL=$input_level
        output "INFO" "设置威胁等级：$THREAT_LEVEL"
    fi
    if ! echo "THREAT_LEVEL=$THREAT_LEVEL" > "$CONFIG_FILE"; then
        output "ERROR" "写入配置文件失败：$CONFIG_FILE（检查权限）"
        return 1
    fi
    chmod 644 "$CONFIG_FILE" 2>/dev/null || {
        output "ERROR" "设置配置文件权限失败：$CONFIG_FILE"
        return 1
    }
    output "SUCCESS" "保存威胁等级：$THREAT_LEVEL"

    while true; do
        output "ACTION" "输入更新 Cron 规则（默认每天 0:00,6:00,12:00,18:00，分钟间隔需 >= 60）："
        read -r cron_schedule
        if [[ -z "$cron_schedule" ]]; then
            cron_schedule="$DEFAULT_UPDATE_CRON"
            output "INFO" "使用默认定时规则：$cron_schedule"
        else
            if ! echo "$cron_schedule" | grep -qE '^[0-9*/,-]+[[:space:]]+[0-9*/,-]+[[:space:]]+[0-9*/,-]+[[:space:]]+[0-9*/,-]+[[:space:]]+[0-9*/,-]+$'; then
                output "ERROR" "无效 Cron 规则：$cron_schedule"
                continue
            fi
            # 检查分钟间隔
            local min_part=$(echo "$cron_schedule" | awk '{print $1}')
            if [[ "$min_part" =~ ^\*/([0-9]+)$ ]]; then
                if [[ ${BASH_REMATCH[1]} -lt 60 ]]; then
                    output "ERROR" "分钟间隔需 >= 60：$cron_schedule"
                    continue
                fi
            fi
            output "INFO" "设置定时规则：$cron_schedule"
        fi
        # 检查清空任务是否实际存在并验证冲突
        if [[ -n "$CLEANUP_CRON" ]]; then
            if crontab -l 2>/dev/null | grep -q "# IPThreat Firewalld Cleanup"; then
                if ! check_cron_conflict "$cron_schedule" "$CLEANUP_CRON" "update" "cleanup"; then
                    continue
                fi
            else
                if [[ -f "$CONFIG_FILE" ]]; then
                    sed -i '/CLEANUP_CRON/d' "$CONFIG_FILE" 2>/dev/null || {
                        output "WARNING" "无法清理配置文件中的 CLEANUP_CRON：$CONFIG_FILE"
                    }
                    output "INFO" "已清理无效的 CLEANUP_CRON 配置"
                    CLEANUP_CRON=""
                fi
            fi
        fi
        break
    done

    IPTHREAT_URL="https://lists.ipthreat.net/file/ipthreat-lists/threat/threat-${THREAT_LEVEL}.txt.gz"
    TEMP_GZ=$(mktemp /tmp/threat-${THREAT_LEVEL}.XXXXXX.gz)
    TEMP_TXT=$(mktemp /tmp/threat-${THREAT_LEVEL}.XXXXXX.txt)

    setup_ipset
    if ! update_ips; then
        output "ERROR" "更新 IP 列表失败"
        return 1
    fi

    if ! cp "$0" "$CRON_SCRIPT_PATH"; then
        output "ERROR" "复制脚本失败：$CRON_SCRIPT_PATH（检查权限）"
        return 1
    fi
    chmod +x "$CRON_SCRIPT_PATH" 2>/dev/null || {
        output "ERROR" "设置脚本权限失败：$CRON_SCRIPT_PATH"
        return 1
    }

    temp_cron=$(mktemp)
    crontab -l > "$temp_cron" 2>/dev/null || true
    sed -i '/# IPThreat Firewalld Update/d' "$temp_cron"
    echo "$cron_schedule /bin/bash $CRON_SCRIPT_PATH --auto-update # IPThreat Firewalld Update" >> "$temp_cron"
    if ! crontab "$temp_cron"; then
        output "ERROR" "设置 crontab 失败（检查 cron 服务）"
        rm -f "$temp_cron"
        return 1
    fi
    rm -f "$temp_cron"
    if ! echo "UPDATE_CRON=\"$cron_schedule\"" >> "$CONFIG_FILE"; then
        output "ERROR" "写入配置文件失败：$CONFIG_FILE（检查权限）"
        return 1
    fi
    output "SUCCESS" "启用定时更新（规则: $cron_schedule, 威胁等级: $THREAT_LEVEL）"
}

enable_auto_cleanup() {
    # 启用定时清空封禁列表
    local temp_cron cleanup_schedule
    output "DEBUG" "开始启用定时清空，CONFIG_FILE=$CONFIG_FILE, MAX_IP_LIMIT=$MAX_IP_LIMIT"
    while true; do
        output "ACTION" "输入清空 IP Cron 规则（默认每月第一天 01:00，分钟间隔需 >= 60）："
        read -r cleanup_schedule
        if [[ -z "$cleanup_schedule" ]]; then
            cleanup_schedule="$DEFAULT_CLEANUP_CRON"
            output "INFO" "使用默认清空规则：$cleanup_schedule"
        else
            if ! echo "$cleanup_schedule" | grep -qE '^[0-9*/,-]+[[:space:]]+[0-9*/,-]+[[:space:]]+[0-9*/,-]+[[:space:]]+[0-9*/,-]+[[:space:]]+[0-9*/,-]+$'; then
                output "ERROR" "无效 Cron 规则：$cleanup_schedule"
                continue
            fi
            # 检查分钟间隔
            local min_part=$(echo "$cleanup_schedule" | awk '{print $1}')
            if [[ "$min_part" =~ ^\*/([0-9]+)$ ]]; then
                if [[ ${BASH_REMATCH[1]} -lt 60 ]]; then
                    output "ERROR" "分钟间隔需 >= 60：$cleanup_schedule"
                    continue
                fi
            fi
            output "INFO" "设置清空规则：$cleanup_schedule"
        fi
        # 检查更新任务是否实际存在并验证冲突
        if [[ -n "$UPDATE_CRON" ]]; then
            if crontab -l 2>/dev/null | grep -q "# IPThreat Firewalld Update"; then
                if ! check_cron_conflict "$cleanup_schedule" "$UPDATE_CRON" "cleanup" "update"; then
                    continue
                fi
            else
                if [[ -f "$CONFIG_FILE" ]]; then
                    sed -i '/UPDATE_CRON/d' "$CONFIG_FILE" 2>/dev/null || {
                        output "WARNING" "无法清理配置文件中的 UPDATE_CRON：$CONFIG_FILE"
                    }
                    output "INFO" "已清理无效的 UPDATE_CRON 配置"
                    UPDATE_CRON=""
                fi
            fi
        fi
        break
    done

    if ! cp "$0" "$CRON_SCRIPT_PATH"; then
        output "ERROR" "复制脚本失败：$CRON_SCRIPT_PATH（检查权限）"
        return 1
    fi
    chmod +x "$CRON_SCRIPT_PATH" 2>/dev/null || {
        output "ERROR" "设置脚本权限失败：$CRON_SCRIPT_PATH"
        return 1
    }

    temp_cron=$(mktemp)
    crontab -l > "$temp_cron" 2>/dev/null || true
    sed -i '/# IPThreat Firewalld Cleanup/d' "$temp_cron"
    echo "$cleanup_schedule /bin/bash $CRON_SCRIPT_PATH --cleanup # IPThreat Firewalld Cleanup" >> "$temp_cron"
    if ! crontab "$temp_cron"; then
        output "ERROR" "设置 crontab 失败（检查 cron 服务）"
        rm -f "$temp_cron"
        return 1
    fi
    rm -f "$temp_cron"
    if ! echo "CLEANUP_CRON=\"$cleanup_schedule\"" >> "$CONFIG_FILE"; then
        output "ERROR" "写入配置文件失败：$CONFIG_FILE（检查权限）"
        return 1
    fi
    chmod 644 "$CONFIG_FILE" 2>/dev/null || {
        output "ERROR" "设置配置文件权限失败：$CONFIG_FILE"
        return 1
    }
    output "SUCCESS" "启用定时清空（规则: $cleanup_schedule）"
}

disable_auto_update() {
    # 禁用定时更新任务
    local temp_cron
    temp_cron=$(mktemp)
    crontab -l > "$temp_cron" 2>/dev/null || true
    sed -i '/# IPThreat Firewalld Update/d' "$temp_cron"
    if ! crontab "$temp_cron"; then
        output "ERROR" "更新 crontab 失败（检查 cron 服务）"
        rm -f "$temp_cron"
        return 1
    fi
    rm -f "$temp_cron"

    if ! crontab -l 2>/dev/null | grep -q "# IPThreat Firewalld Cleanup"; then
        if [[ -f "$CRON_SCRIPT_PATH" ]]; then
            rm -f "$CRON_SCRIPT_PATH" 2>/dev/null || {
                output "ERROR" "删除脚本失败：$CRON_SCRIPT_PATH"
                return 1
            }
            output "INFO" "删除脚本：$CRON_SCRIPT_PATH"
        fi
        if [[ -f "$CONFIG_FILE" ]]; then
            rm -f "$CONFIG_FILE" 2>/dev/null || {
                output "ERROR" "删除配置文件失败：$CONFIG_FILE"
                return 1
            }
            output "INFO" "删除配置文件：$CONFIG_FILE"
        fi
    else
        if [[ -f "$CONFIG_FILE" ]]; then
            sed -i '/UPDATE_CRON/d' "$CONFIG_FILE" 2>/dev/null || {
                output "ERROR" "更新配置文件失败：$CONFIG_FILE"
                return 1
            }
        fi
    fi
    output "SUCCESS" "禁用定时更新"
}

disable_auto_cleanup() {
    # 禁用定时清空任务
    local temp_cron
    temp_cron=$(mktemp)
    crontab -l > "$temp_cron" 2>/dev/null || true
    sed -i '/# IPThreat Firewalld Cleanup/d' "$temp_cron"
    if ! crontab "$temp_cron"; then
        output "ERROR" "更新 crontab 失败（检查 cron 服务）"
        rm -f "$temp_cron"
        return 1
    fi
    rm -f "$temp_cron"
    if [[ -f "$CONFIG_FILE" ]]; then
        sed -i '/CLEANUP_CRON/d' "$CONFIG_FILE" 2>/dev/null || {
            output "ERROR" "更新配置文件失败：$CONFIG_FILE"
            return 1
        }
    fi

    if ! crontab -l 2>/dev/null | grep -q "# IPThreat Firewalld Update"; then
        if [[ -f "$CRON_SCRIPT_PATH" ]]; then
            rm -f "$CRON_SCRIPT_PATH" 2>/dev/null || {
                output "ERROR" "删除脚本失败：$CRON_SCRIPT_PATH"
                return 1
            }
            output "INFO" "删除脚本：$CRON_SCRIPT_PATH"
        fi
        if [[ -f "$CONFIG_FILE" ]]; then
            rm -f "$CONFIG_FILE" 2>/dev/null || {
                output "ERROR" "删除配置文件失败：$CONFIG_FILE"
                return 1
            }
            output "INFO" "删除配置文件：$CONFIG_FILE"
        fi
    fi
    output "SUCCESS" "禁用定时清空"
}

view_cron_jobs() {
    # 查看当前定时任务
    local has_jobs=0
    if crontab -l 2>/dev/null | grep -q "# IPThreat Firewalld Update"; then
        output "INFO" "定时更新任务："
        crontab -l 2>/dev/null | grep "# IPThreat Firewalld Update"
        has_jobs=1
    fi
    if crontab -l 2>/dev/null | grep -q "# IPThreat Firewalld Cleanup"; then
        output "INFO" "定时清空任务："
        crontab -l 2>/dev/null | grep "# IPThreat Firewalld Cleanup"
        has_jobs=1
    fi
    if [[ $has_jobs -eq 0 ]]; then
        output "INFO" "无定时任务"
    fi
}

update_ips() {
    # 执行 IP 列表更新
    download_ipthreat_list && filter_and_add_ips
}

show_menu() {
    # 显示交互式菜单
    local display_threat_level="未设置"
    if [[ -f "$CONFIG_FILE" ]]; then
        source <(grep -E '^(THREAT_LEVEL|UPDATE_CRON|CLEANUP_CRON)=' "$CONFIG_FILE")
        if [[ "$THREAT_LEVEL" =~ ^[0-9]+$ && "$THREAT_LEVEL" -ge 0 && "$THREAT_LEVEL" -le 100 ]]; then
            display_threat_level="$THREAT_LEVEL"
        fi
    fi
    echo -e "${COLORS[WHITE]}Firewalld IP 封禁管理${COLORS[RESET]}"
    echo "区域: $ZONE"
    echo "威胁等级: $display_threat_level (0~100)"
    echo "IP 使用量: $(get_ipset_usage)"
    echo "---------------------"
    echo "1. 启用自动更新"
    echo "2. 禁用自动更新"
    echo "3. 启用自动清空"
    echo "4. 禁用自动清空"
    echo "5. 查看定时任务"
    echo "6. 添加封禁 IP"
    echo "7. 移除封禁 IP"
    echo "8. 清空封禁列表"
    echo "0. 退出"
    echo "---------------------"
    read -p "请选择操作: " choice
    case $choice in
        0) exit 0 ;;
        1) enable_auto_update ;;
        2) disable_auto_update ;;
        3) enable_auto_cleanup ;;
        4) disable_auto_cleanup ;;
        5) view_cron_jobs ;;
        6) manual_add_ips ;;
        7) manual_remove_ips ;;
        8) remove_all_ips ;;
        *) output "ERROR" "无效选项：$choice" ;;
    esac
}

main() {
    # 主函数，处理命令行参数并启动脚本
    local auto_update=0 cleanup=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --auto-update) auto_update=1 AUTO_MODE=1 ;;
            --cleanup) cleanup=1 AUTO_MODE=1 ;;
        esac
        shift
    done

    check_dependencies
    select_zone

    if [[ $auto_update -eq 1 ]]; then
        if [[ -f "$CONFIG_FILE" ]]; then
            source <(grep -E '^(THREAT_LEVEL|UPDATE_CRON|CLEANUP_CRON)=' "$CONFIG_FILE")
            output "INFO" "加载威胁等级：$THREAT_LEVEL"
        else
            output "INFO" "无配置文件，使用默认威胁等级：$DEFAULT_THREAT_LEVEL"
            THREAT_LEVEL=$DEFAULT_THREAT_LEVEL
        fi

        if ! [[ "$THREAT_LEVEL" =~ ^[0-9]+$ ]] || [[ "$THREAT_LEVEL" -lt 0 ]] || [[ "$THREAT_LEVEL" -gt 100 ]]; then
            output "ERROR" "无效威胁等级：$THREAT_LEVEL，使用默认：$DEFAULT_THREAT_LEVEL"
            THREAT_LEVEL=$DEFAULT_THREAT_LEVEL
        fi

        IPTHREAT_URL="https://lists.ipthreat.net/file/ipthreat-lists/threat/threat-${THREAT_LEVEL}.txt.gz"
        TEMP_GZ=$(mktemp /tmp/threat-${THREAT_LEVEL}.XXXXXX.gz)
        TEMP_TXT=$(mktemp /tmp/threat-${THREAT_LEVEL}.XXXXXX.txt)

        output "INFO" "开始定时更新，威胁等级：$THREAT_LEVEL"
        setup_ipset
        update_ips
        output "SUCCESS" "定时更新完成"
    elif [[ $cleanup -eq 1 ]]; then
        output "INFO" "开始清空封禁 IP"
        remove_all_ips
        output "SUCCESS" "清空封禁 IP 完成"
    else
        while true; do
            show_menu
        done
    fi
}

main "$@"
