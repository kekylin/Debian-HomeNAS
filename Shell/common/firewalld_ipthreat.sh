#!/bin/bash

# ======================= 颜色输出模块 =======================
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
    local type="${1}" msg="${2}" custom_color="${3}" is_log="${4:-true}"
    local color="${custom_color:-${COLORS[$type]}}"
    local prefix=""
    [[ "${is_log}" == "true" ]] && prefix="[${type}] "
    printf "%b%s%b\n" "${color}" "${prefix}${msg}" "${COLORS[RESET]}"
}

# ======================= 常量定义 =======================
CONFIG_FILE="/etc/firewalld/ipthreat_config"
THREAT_LEVEL=50  # 默认威胁等级
IPTHREAT_URL="https://lists.ipthreat.net/file/ipthreat-lists/threat/threat-${THREAT_LEVEL}.txt.gz"
ZONE="drop"
IPSET_NAME_IPV4="ipthreat_block"
IPSET_NAME_IPV6="ipthreat_block_ipv6"
MAX_RANGE_SIZE=1000  # 最大展开范围，超出建议转为 CIDR
MAX_IP_LIMIT=65536   # 最大 IP 数量限制，与 IPSet maxelem 一致
BATCH_SIZE=10000     # 每批添加的 IP 数量
MAX_MANUAL_INPUT=1000  # 手动输入的最大 IP 条数
CRON_SCRIPT_PATH="/etc/firewalld/.firewalld_ipthreat.sh"

# 加载配置文件中的威胁等级和清理计划
[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

# ======================= 临时文件管理 =======================
TEMP_GZ=$(mktemp /tmp/threat-${THREAT_LEVEL}.XXXXXX.gz)
TEMP_TXT=$(mktemp /tmp/threat-${THREAT_LEVEL}.XXXXXX.txt)
TEMP_IP_LIST_IPV4=$(mktemp /tmp/valid_ips_ipv4.XXXXXX.txt)
TEMP_IP_LIST_IPV6=$(mktemp /tmp/valid_ips_ipv6.XXXXXX.txt)

trap 'rm -f "$TEMP_GZ" "$TEMP_TXT" "$TEMP_IP_LIST_IPV4" "$TEMP_IP_LIST_IPV6"; exit 1' INT TERM EXIT

# ======================= IP 地址验证和范围解析 =======================
valid_ipv4() {
    local ip=$1
    if [[ $ip =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]]; then
        local a=${BASH_REMATCH[1]} b=${BASH_REMATCH[2]} c=${BASH_REMATCH[3]} d=${BASH_REMATCH[4]}
        [[ $a -le 255 && $b -le 255 && $c -le 255 && $d -le 255 && $a -ge 0 ]]
    else
        return 1
    fi
}

valid_ipv6() {
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
    local input=$1
    local prefix mask
    if [[ $input =~ ^([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})/([0-9]{1,2})$ ]]; then
        prefix=${BASH_REMATCH[1]}
        mask=${BASH_REMATCH[2]}
        if [[ ! $mask =~ ^[0-9]+$ ]] || [[ $mask -gt 32 ]] || [[ $mask -lt 0 ]]; then
            output "WARNING" "无效 IPv4 CIDR mask: $mask in $input" "" "true"
            return 1
        fi
        if valid_ipv4 "$prefix"; then
            echo "$prefix $mask"
            return 0
        else
            output "WARNING" "无效 IPv4 CIDR 前缀: $prefix in $input" "" "true"
            return 1
        fi
    else
        return 1
    fi
}

valid_cidr_ipv6() {
    local input=$1
    local prefix mask
    if [[ $input =~ ^([0-9a-fA-F:]+)/([0-9]{1,3})$ ]]; then
        prefix=${BASH_REMATCH[1]}
        mask=${BASH_REMATCH[2]}
        if [[ ! $mask =~ ^[0-9]+$ ]] || [[ $mask -gt 128 ]] || [[ $mask -lt 0 ]]; then
            output "WARNING" "无效 IPv6 CIDR mask: $mask in $input" "" "true"
            return 1
        fi
        if valid_ipv6 "$prefix"; then
            echo "$prefix $mask"
            return 0
        else
            output "WARNING" "无效 IPv6 CIDR 前缀: $prefix in $input" "" "true"
            return 1
        fi
    else
        return 1
    fi
}

expand_ip_range() {
    local input=$1 output_file_ipv4=$2 output_file_ipv6=$3
    local start_ip end_ip prefix mask ip_count protocol awk_output result

    [[ -z "$input" ]] && {
        output "WARNING" "空输入，跳过处理" "" "true"
        return 1
    }

    # 优先匹配 CIDR
    result=$(valid_cidr_ipv4 "$input")
    if [[ $? -eq 0 ]]; then
        read -r prefix mask <<< "$result"
        ip_count=$((2 ** (32 - mask)))
        if [[ $ip_count -gt $MAX_IP_LIMIT ]]; then
            output "WARNING" "IPv4 CIDR $input 包含 $ip_count 个 IP，超出上限 $MAX_IP_LIMIT，跳过" "" "true"
            return 1
        fi
        echo "$input" >> "$output_file_ipv4"
        output "INFO" "解析 IPv4 CIDR $input 为 $ip_count 个 IP 地址" "" "true"
        return 0
    fi
    result=$(valid_cidr_ipv6 "$input")
    if [[ $? -eq 0 ]]; then
        read -r prefix mask <<< "$result"
        ip_count=$((2 ** (128 - mask)))
        if [[ $ip_count -gt $MAX_IP_LIMIT ]]; then
            output "WARNING" "IPv6 CIDR $input 包含 $ip_count 个 IP，超出上限 $MAX_IP_LIMIT，跳过" "" "true"
            return 1
        fi
        echo "$input" >> "$output_file_ipv6"
        output "INFO" "解析 IPv6 CIDR $input 为 $ip_count 个 IP 地址" "" "true"
        return 0
    fi

    # 匹配范围
    if [[ $input =~ ^([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})-([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})$ ]]; then
        start_ip=${BASH_REMATCH[1]}
        end_ip=${BASH_REMATCH[2]}
        if ! valid_ipv4 "$start_ip"; then
            output "WARNING" "无效 IPv4 范围起始 IP: $start_ip in $input" "" "true"
            return 1
        fi
        if ! valid_ipv4 "$end_ip"; then
            output "WARNING" "无效 IPv4 范围结束 IP: $end_ip in $input" "" "true"
            return 1
        fi
        IFS='.' read -r a b c d <<< "$start_ip"
        start_num=$(( (a * 16777216) + (b * 65536) + (c * 256) + d ))
        IFS='.' read -r a b c d <<< "$end_ip"
        end_num=$(( (a * 16777216) + (b * 65536) + (c * 256) + d ))
        if [[ $start_num -gt $end_num ]]; then
            output "WARNING" "无效 IPv4 范围（起始 IP 大于结束 IP）: $input" "" "true"
            return 1
        fi
        ip_count=$((end_num - start_num + 1))
        if [[ $ip_count -gt $MAX_IP_LIMIT ]]; then
            output "WARNING" "IPv4 范围 $input 包含 $ip_count 个 IP，超出上限 $MAX_IP_LIMIT，跳过" "" "true"
            return 1
        fi
        if [[ $ip_count -gt $MAX_RANGE_SIZE ]]; then
            output "WARNING" "IPv4 范围过大（$ip_count 个 IP），请使用 CIDR: $input" "" "true"
            return 1
        fi
        awk_output=$(awk -v start="$start_num" -v end="$end_num" \
            'BEGIN { for (i=start; i<=end; i++) { a=int(i/16777216); b=int((i%16777216)/65536); c=int((i%65536)/256); d=i%256; printf "%d.%d.%d.%d\n", a, b, c, d } }' 2>&1)
        if [[ $? -ne 0 ]]; then
            output "ERROR" "解析 IPv4 范围 $input 失败: $awk_output" "" "true"
            return 1
        fi
        echo "$awk_output" >> "$output_file_ipv4"
        output "INFO" "解析 IPv4 范围 $input 为 $ip_count 个 IP 地址" "" "true"
        return 0
    elif [[ $input =~ ^([0-9a-fA-F:]+)-([0-9a-fA-F:]+)$ ]]; then
        start_ip=${BASH_REMATCH[1]}
        end_ip=${BASH_REMATCH[2]}
        if ! valid_ipv6 "$start_ip" || ! valid_ipv6 "$end_ip"; then
            output "WARNING" "无效 IPv6 范围: $input" "" "true"
            return 1
        fi
        echo "$start_ip" >> "$output_file_ipv6"
        echo "$end_ip" >> "$output_file_ipv6"
        output "INFO" "解析 IPv6 范围 $input（简化为边界 IP）" "" "true"
        return 0
    fi

    # 匹配单 IP
    protocol=$(valid_ip "$input")
    if [[ $? -eq 0 ]]; then
        if [[ $protocol == "ipv4" ]]; then
            echo "$input" >> "$output_file_ipv4"
            output "INFO" "解析单 IPv4 IP: $input" "" "true"
        else
            echo "$input" >> "$output_file_ipv6"
            output "INFO" "解析单 IPv6 IP: $input" "" "true"
        fi
        return 0
    fi

    output "WARNING" "无效 IP 输入: $input" "" "true"
    return 1
}

# ======================= 公共函数 =======================
check_dependencies() {
    for cmd in firewall-cmd wget gzip awk sed grep sort comm split head crontab; do
        command -v "$cmd" &>/dev/null || {
            output "ERROR" "缺少依赖命令: $cmd" "" "true"
            exit 1
        }
    done
    systemctl is-active firewalld &>/dev/null || {
        output "ERROR" "Firewalld 服务未运行" "" "true"
        exit 1
    }
    systemctl is-active cron &>/dev/null || systemctl is-active crond &>/dev/null || {
        output "ERROR" "Cron 服务未运行，请启动 cron 服务（例如：systemctl start crond）" "" "true"
        exit 1
    }
}

setup_ipset() {
    if firewall-cmd --permanent --get-ipsets | grep -qw "$IPSET_NAME_IPV4"; then
        : # 跳过提示
    else
        output "INFO" "创建 IPv4 IPSet: $IPSET_NAME_IPV4 用于 IP 封禁" "" "true"
        if ! firewall-cmd --permanent --new-ipset="$IPSET_NAME_IPV4" --type=hash:ip --option=family=inet --option=maxelem=$MAX_IP_LIMIT &>/dev/null; then
            output "ERROR" "创建 IPv4 IPSet 失败，请检查 Firewalld 配置或删除现有 IPSet" "" "true"
            exit 1
        fi
    fi
    if ! firewall-cmd --permanent --zone="$ZONE" --list-sources | grep -qw "ipset:$IPSET_NAME_IPV4"; then
        output "INFO" "将 IPv4 IPSet $IPSET_NAME_IPV4 绑定到区域 $ZONE 以封禁 IP" "" "true"
        if ! firewall-cmd --permanent --zone="$ZONE" --add-source="ipset:$IPSET_NAME_IPV4" &>/dev/null; then
            output "ERROR" "绑定 IPv4 IPSet 到区域失败" "" "true"
            exit 1
        fi
    fi

    if firewall-cmd --permanent --get-ipsets | grep -qw "$IPSET_NAME_IPV6"; then
        : # 跳过提示
    else
        output "INFO" "创建 IPv6 IPSet: $IPSET_NAME_IPV6 用于 IP 封禁" "" "true"
        if ! firewall-cmd --permanent --new-ipset="$IPSET_NAME_IPV6" --type=hash:ip --option=family=inet6 --option=maxelem=$MAX_IP_LIMIT &>/dev/null; then
            output "ERROR" "创建 IPv6 IPSet 失败，请检查 Firewalld 配置或删除现有 IPSet" "" "true"
            exit 1
        fi
    fi
    if ! firewall-cmd --permanent --zone="$ZONE" --list-sources | grep -qw "ipset:$IPSET_NAME_IPV6"; then
        output "INFO" "将 IPv6 IPSet $IPSET_NAME_IPV6 绑定到区域 $ZONE 以封禁 IP" "" "true"
        if ! firewall-cmd --permanent --zone="$ZONE" --add-source="ipset:$IPSET_NAME_IPV6" &>/dev/null; then
            output "ERROR" "绑定 IPv6 IPSet 到区域失败" "" "true"
            exit 1
        fi
    fi
}

select_zone() {
    firewall-cmd --get-zones | grep -qw "$ZONE" || {
        output "ERROR" "无效的 Firewalld 区域: $ZONE" "" "true"
        exit 1
    }
}

get_ipset_usage() {
    local ipv4_count ipv6_count
    if firewall-cmd --permanent --get-ipsets | grep -qw "$IPSET_NAME_IPV4"; then
        ipv4_count=$(firewall-cmd --permanent --ipset="$IPSET_NAME_IPV4" --get-entries | wc -l)
        ipv4_status="IPv4: $ipv4_count/$MAX_IP_LIMIT (剩余: $((MAX_IP_LIMIT - ipv4_count)))"
    else
        ipv4_status="IPv4: 未配置"
    fi
    if firewall-cmd --permanent --get-ipsets | grep -qw "$IPSET_NAME_IPV6"; then
        ipv6_count=$(firewall-cmd --permanent --ipset="$IPSET_NAME_IPV6" --get-entries | wc -l)
        ipv6_status="IPv6: $ipv6_count/$MAX_IP_LIMIT (剩余: $((MAX_IP_LIMIT - ipv6_count)))"
    else
        ipv6_status="IPv6: 未配置"
    fi
    echo "$ipv4_status, $ipv6_status"
}

download_ipthreat_list() {
    output "ACTION" "正在下载威胁等级 ${THREAT_LEVEL} 的 IP 列表..." "" "true"
    if ! wget -q "$IPTHREAT_URL" -O "$TEMP_GZ"; then
        output "ERROR" "下载威胁等级 ${THREAT_LEVEL} 的 IP 列表失败" "" "true"
        return 1
    fi
    if ! gzip -dc "$TEMP_GZ" > "$TEMP_TXT"; then
        output "ERROR" "解压威胁等级 ${THREAT_LEVEL} 的 IP 列表失败" "" "true"
        rm -f "$TEMP_GZ"
        return 1
    fi
    rm -f "$TEMP_GZ"
    output "SUCCESS" "威胁等级 ${THREAT_LEVEL} 的 IP 列表下载并解压成功" "" "true"
}

process_ip_list() {
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

    # 解析输入文件中的 IP
    awk '!/^#/ && NF {print $1}' "$input_file" | while IFS= read -r ip; do
        [[ -z "$ip" ]] && continue
        expand_ip_range "$ip" "$temp_file_ipv4" "$temp_file_ipv6" || {
            output "ERROR" "处理 IP $ip 失败" "" "true"
        }
    done

    # 检查现有 IPSet 中的条目
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

    # 去重输入的 IP
    if ! sort -u "$temp_file_ipv4" > "$output_file_ipv4" 2>/dev/null; then
        output "ERROR" "IPv4 IP 去重失败" "" "true"
        return 1
    fi
    if ! sort -u "$temp_file_ipv6" > "$output_file_ipv6" 2>/dev/null; then
        output "ERROR" "IPv6 IP 去重失败" "" "true"
        return 1
    fi

    # 计算输入的 IP 数量
    input_ipv4_count=$(wc -l < "$output_file_ipv4")
    input_ipv6_count=$(wc -l < "$output_file_ipv6")

    # 筛选出需要添加或移除的 IP
    local new_output_ipv4=$(mktemp /tmp/new_output_ipv4.XXXXXX.txt)
    local new_output_ipv6=$(mktemp /tmp/new_output_ipv6.XXXXXX.txt)
    if [[ "$mode" == "add" ]]; then
        if ! comm -23 "$output_file_ipv4" "$existing_ips_file_ipv4" > "$new_output_ipv4" 2>/dev/null; then
            output "ERROR" "IPv4 IP 比较失败" "" "true"
            return 1
        fi
        if ! comm -23 "$output_file_ipv6" "$existing_ips_file_ipv6" > "$new_output_ipv6" 2>/dev/null; then
            output "ERROR" "IPv6 IP 比较失败" "" "true"
            return 1
        fi
    elif [[ "$mode" == "remove" ]]; then
        if ! comm -12 "$output_file_ipv4" "$existing_ips_file_ipv4" > "$new_output_ipv4" 2>/dev/null; then
            output "ERROR" "IPv4 IP 比较失败" "" "true"
            return 1
        fi
        if ! comm -12 "$output_file_ipv6" "$existing_ips_file_ipv6" > "$new_output_ipv6" 2>/dev/null; then
            output "ERROR" "IPv6 IP 比较失败" "" "true"
            return 1
        fi
    fi

    mv "$new_output_ipv4" "$output_file_ipv4"
    mv "$new_output_ipv6" "$output_file_ipv6"
    rm -f "$temp_file_ipv4" "$temp_file_ipv6" "$existing_ips_file_ipv4" "$existing_ips_file_ipv6"

    # 计算需要处理的 IP 数量
    ipv4_count=$(wc -l < "$output_file_ipv4")
    ipv6_count=$(wc -l < "$output_file_ipv6")
    if firewall-cmd --permanent --get-ipsets | grep -qw "$IPSET_NAME_IPV4"; then
        current_ipv4_count=$(firewall-cmd --permanent --ipset="$IPSET_NAME_IPV4" --get-entries | wc -l)
    else
        current_ipv4_count=0
    fi
    if firewall-cmd --permanent --get-ipsets | grep -qw "$IPSET_NAME_IPV6"; then
        current_ipv6_count=$(firewall-cmd --permanent --ipset="$IPSET_NAME_IPV6" --get-entries | wc -l)
    else
        current_ipv6_count=0
    fi

    # 处理添加模式
    if [[ "$mode" == "add" ]]; then
        # 计算剩余容量
        ipv4_remaining=$((MAX_IP_LIMIT - current_ipv4_count))
        ipv6_remaining=$((MAX_IP_LIMIT - current_ipv6_count))
        ipv4_to_add=$ipv4_count
        ipv6_to_add=$ipv6_count
        ipv4_skipped=0
        ipv6_skipped=0

        # 如果超出上限，截取部分 IP
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
    output "INFO" "输入 IPv4 IP 数: $input_ipv4_count, IPv6 IP 数: $input_ipv6_count" "" "true"
    if [[ "$mode" == "add" ]]; then
        if [[ $input_ipv4_count -eq 0 && $input_ipv6_count -eq 0 ]]; then
            output "INFO" "未提供任何有效 IP" "" "true"
        elif [[ $ipv4_to_add -eq 0 && $ipv6_to_add -eq 0 ]]; then
            if [[ $input_ipv4_count -gt 0 || $input_ipv6_count -gt 0 ]]; then
                output "INFO" "所有输入 IP 已存在于封禁列表，无需重复添加" "" "true"
            fi
        else
            output "INFO" "将封禁 IPv4 IP: $ipv4_to_add 个, IPv6 IP: $ipv6_to_add 个" "" "true"
            if [[ $ipv4_skipped -gt 0 || $ipv6_skipped -gt 0 ]]; then
                output "WARNING" "IP 超出上限 $MAX_IP_LIMIT，IPv4 跳过 $ipv4_skipped 个，IPv6 跳过 $ipv6_skipped 个" "" "true"
            fi
        fi
    elif [[ "$mode" == "remove" ]]; then
        if [[ $input_ipv4_count -eq 0 && $input_ipv6_count -eq 0 ]]; then
            output "INFO" "未提供任何有效 IP" "" "true"
        elif [[ $ipv4_count -eq 0 && $ipv6_count -eq 0 ]]; then
            output "INFO" "输入的 IP 未在封禁列表中" "" "true"
        else
            output "INFO" "将解除 IPv4 IP: $ipv4_count 个, IPv6 IP: $ipv6_count 个" "" "true"
        fi
    fi

    # 执行 IP 变更
    if [[ $ipv4_count -eq 0 && $ipv6_count -eq 0 ]]; then
        output "INFO" "没有 IP 需要处理" "" "true"
    else
        apply_ip_changes "$output_file_ipv4" "$IPSET_NAME_IPV4" "ipv4" "$mode" &
        apply_ip_changes "$output_file_ipv6" "$IPSET_NAME_IPV6" "ipv6" "$mode" &
        wait
    fi
}

apply_ip_changes() {
    local ip_file=$1 ipset_name=$2 protocol=$3 mode=$4
    local total_ips batch_file batch_count batch_index current_count remaining batch_size

    total_ips=$(wc -l < "$ip_file")
    if [[ $total_ips -eq 0 ]]; then
        output "INFO" "没有 $protocol IP 需要处理" "" "true"
        return
    fi

    # 分批处理
    batch_file=$(mktemp /tmp/batch_ips.XXXXXX.txt)
    if firewall-cmd --permanent --get-ipsets | grep -qw "$ipset_name"; then
        current_count=$(firewall-cmd --permanent --ipset="$ipset_name" --get-entries | wc -l)
    else
        current_count=0
    fi
    remaining=$((MAX_IP_LIMIT - current_count))
    split -l "$BATCH_SIZE" "$ip_file" "$batch_file." --additional-suffix=.txt
    batch_count=$(ls "$batch_file."*.txt | wc -l)
    batch_index=1

    for batch in "$batch_file."*.txt; do
        if [[ ! -f "$batch" ]]; then
            output "WARNING" "批次文件 $batch 不存在，跳过" "" "true"
            continue
        fi
        batch_size=$(wc -l < "$batch")
        if [[ "$mode" == "add" && $batch_size -gt $remaining ]]; then
            batch_size=$remaining
            head -n "$batch_size" "$batch" > "${batch}.tmp" && mv "${batch}.tmp" "$batch"
            output "WARNING" "批次 $batch_index 调整为 $batch_size 个 $protocol IP 以避免超限" "" "true"
        fi
        if [[ $batch_size -eq 0 ]]; then
            output "INFO" "批次 $batch_index 无 $protocol IP 可封禁（IPSet 已满）" "" "true"
            rm -f "$batch"
            continue
        fi
        output "ACTION" "正在处理 $protocol IP 批次 $batch_index/$batch_count，包含 $batch_size 个地址 ($mode)..." "" "true"
        if [[ "$mode" == "add" ]]; then
            if ! output=$(firewall-cmd --permanent --ipset="$ipset_name" --add-entries-from-file="$batch" 2>&1); then
                if [[ $output =~ "ipset is full" ]]; then
                    output "ERROR" "IPSet $ipset_name 已满，无法封禁更多 $protocol IP" "" "true"
                else
                    output "ERROR" "封禁 $protocol IP 到 IPSet $ipset_name 失败: $output" "" "true"
                fi
                rm -f "$batch_file."*.txt
                return 1
            fi
        elif [[ "$mode" == "remove" ]]; then
            if ! output=$(firewall-cmd --permanent --ipset="$ipset_name" --remove-entries-from-file="$batch" 2>&1); then
                output "ERROR" "解除 $protocol IP 封禁从 IPSet $ipset_name 失败: $output" "" "true"
                rm -f "$batch_file."*.txt
                return 1
            fi
        fi
        remaining=$((remaining - batch_size))
        ((batch_index++))
        rm -f "$batch"
    done

    if ! output=$(firewall-cmd --reload 2>&1); then
        output "ERROR" "Firewalld 规则重载失败: $output" "" "true"
        rm -f "$batch_file."*.txt
        return 1
    fi

    if [[ "$mode" == "add" ]]; then
        output "SUCCESS" "成功封禁 $total_ips 个 $protocol IP" "" "true"
    else
        output "SUCCESS" "成功解除 $total_ips 个 $protocol IP 封禁" "" "true"
    fi
    rm -f "$batch_file."*.txt
}

filter_and_add_ips() {
    [[ ! -f "$TEMP_TXT" ]] && {
        output "ERROR" "IP 列表文件不存在" "" "true"
        return 1
    }
    setup_ipset
    process_ip_list "$TEMP_TXT" "$TEMP_IP_LIST_IPV4" "$TEMP_IP_LIST_IPV6" "add"
}

manual_add_ips() {
    output "ACTION" "请输入要封禁的 IP（每行一个，支持单 IP、CIDR 或范围，最多 $MAX_MANUAL_INPUT 条）：" "" "true"
    setup_ipset
    : > "$TEMP_IP_LIST_IPV4"
    : > "$TEMP_IP_LIST_IPV6"
    local temp_input=$(mktemp /tmp/manual_ips.XXXXXX.txt)
    local line_count=0

    while read -r ip && [[ -n "$ip" ]]; do
        ((line_count++))
        if [[ $line_count -gt $MAX_MANUAL_INPUT ]]; then
            output "ERROR" "输入的 IP 条数超过上限 $MAX_MANUAL_INPUT，请分批输入" "" "true"
            rm -f "$temp_input"
            return 1
        fi
        echo "$ip" >> "$temp_input"
    done

    [[ ! -s "$temp_input" ]] && {
        output "ERROR" "未提供任何 IP" "" "true"
        rm -f "$temp_input"
        return 1
    }

    process_ip_list "$temp_input" "$TEMP_IP_LIST_IPV4" "$TEMP_IP_LIST_IPV6" "add"
    rm -f "$temp_input"
}

manual_remove_ips() {
    if ! firewall-cmd --permanent --get-ipsets | grep -qw "$IPSET_NAME_IPV4" && ! firewall-cmd --permanent --get-ipsets | grep -qw "$IPSET_NAME_IPV6"; then
        output "INFO" "无封禁的 IP 或 IPSet 未配置" "" "true"
        return
    fi
    output "ACTION" "请输入要解除封禁的 IP（每行一个，支持单 IP、CIDR 或范围，最多 $MAX_MANUAL_INPUT 条）：" "" "true"
    : > "$TEMP_IP_LIST_IPV4"
    : > "$TEMP_IP_LIST_IPV6"
    local temp_input=$(mktemp /tmp/manual_ips.XXXXXX.txt)
    local line_count=0

    while read -r ip && [[ -n "$ip" ]]; do
        ((line_count++))
        if [[ $line_count -gt $MAX_MANUAL_INPUT ]]; then
            output "ERROR" "输入的 IP 条数超过上限 $MAX_MANUAL_INPUT，请分批输入" "" "true"
            rm -f "$temp_input"
            return 1
        fi
        echo "$ip" >> "$temp_input"
    done

    [[ ! -s "$temp_input" ]] && {
        output "ERROR" "未提供任何 IP" "" "true"
        rm -f "$temp_input"
        return 1
    }

    process_ip_list "$temp_input" "$TEMP_IP_LIST_IPV4" "$TEMP_IP_LIST_IPV6" "remove"
    rm -f "$temp_input"
}

remove_all_ips() {
    local sources_ipv4 sources_ipv6 drop_xml_file="/etc/firewalld/zones/drop.xml"
    local ipset_bound_ipv4 ipset_bound_ipv6 drop_has_other_configs

    # 检查是否存在 IPSet
    if ! firewall-cmd --permanent --get-ipsets | grep -qw "$IPSET_NAME_IPV4" && ! firewall-cmd --permanent --get-ipsets | grep -qw "$IPSET_NAME_IPV6"; then
        output "INFO" "无封禁的 IP 或 IPSet 未配置" "" "true"
        return
    fi

    # 获取当前 IPSet 中的条目
    sources_ipv4=$(firewall-cmd --permanent --ipset="$IPSET_NAME_IPV4" --get-entries 2>/dev/null)
    sources_ipv6=$(firewall-cmd --permanent --ipset="$IPSET_NAME_IPV6" --get-entries 2>/dev/null)

    if [[ -z "$sources_ipv4" && -z "$sources_ipv6" ]]; then
        output "INFO" "当前无 IP 被封禁" "" "true"
    else
        # 清空 IPv4 和 IPv6 IPSet
        if [[ -n "$sources_ipv4" ]]; then
            echo "$sources_ipv4" | tr ' ' '\n' > "$TEMP_IP_LIST_IPV4"
            apply_ip_changes "$TEMP_IP_LIST_IPV4" "$IPSET_NAME_IPV4" "ipv4" "remove"
        fi
        if [[ -n "$sources_ipv6" ]]; then
            echo "$sources_ipv6" | tr ' ' '\n' > "$TEMP_IP_LIST_IPV6"
            apply_ip_changes "$TEMP_IP_LIST_IPV6" "$IPSET_NAME_IPV6" "ipv6" "remove"
        fi
    fi

    # 检查 drop 区域是否绑定了脚本创建的 IPSet
    ipset_bound_ipv4=$(firewall-cmd --permanent --zone=drop --list-sources | grep -w "ipset:$IPSET_NAME_IPV4" || true)
    ipset_bound_ipv6=$(firewall-cmd --permanent --zone=drop --list-sources | grep -w "ipset:$IPSET_NAME_IPV6" || true)

    # 移除 drop 区域中的 IPSet 绑定
    if [[ -n "$ipset_bound_ipv4" ]]; then
        output "INFO" "从 drop 区域移除 IPv4 IPSet 绑定: $IPSET_NAME_IPV4" "" "true"
        if ! firewall-cmd --permanent --zone=drop --remove-source="ipset:$IPSET_NAME_IPV4" &>/dev/null; then
            output "ERROR" "无法从 drop 区域移除 IPv4 IPSet 绑定" "" "true"
            return 1
        fi
    fi
    if [[ -n "$ipset_bound_ipv6" ]]; then
        output "INFO" "从 drop 区域移除 IPv6 IPSet 绑定: $IPSET_NAME_IPV6" "" "true"
        if ! firewall-cmd --permanent --zone=drop --remove-source="ipset:$IPSET_NAME_IPV6" &>/dev/null; then
            output "ERROR" "无法从 drop 区域移除 IPv6 IPSet 绑定" "" "true"
            return 1
        fi
    fi

    # 删除 IPSet
    if firewall-cmd --permanent --get-ipsets | grep -qw "$IPSET_NAME_IPV4"; then
        output "INFO" "删除 IPv4 IPSet: $IPSET_NAME_IPV4" "" "true"
        if ! firewall-cmd --permanent --delete-ipset="$IPSET_NAME_IPV4" &>/dev/null; then
            output "ERROR" "无法删除 IPv4 IPSet" "" "true"
            return 1
        fi
    fi
    if firewall-cmd --permanent --get-ipsets | grep -qw "$IPSET_NAME_IPV6"; then
        output "INFO" "删除 IPv6 IPSet: $IPSET_NAME_IPV6" "" "true"
        if ! firewall-cmd --permanent --delete-ipset="$IPSET_NAME_IPV6" &>/dev/null; then
            output "ERROR" "无法删除 IPv6 IPSet" "" "true"
            return 1
        fi
    fi

    # 检查 drop 区域是否还有其他配置（来源、服务、端口等）
    drop_has_other_configs=$(firewall-cmd --permanent --zone=drop --list-all | grep -E "services:|ports:|protocols:|masquerade:|forward-ports:|source-ports:|icmp-blocks:|rich rules:" | grep -v "sources: $" || true)
    if [[ -z "$drop_has_other_configs" ]]; then
        # drop 区域为空，删除其配置文件
        if [[ -f "$drop_xml_file" ]]; then
            output "INFO" "drop 区域为空，正在删除配置文件: $drop_xml_file" "" "true"
            if ! rm -f "$drop_xml_file"; then
                output "ERROR" "无法删除 drop 区域配置文件: $drop_xml_file" "" "true"
                return 1
            fi
        fi
    fi

    # 重新加载 Firewalld 以应用更改
    if ! firewall-cmd --reload &>/dev/null; then
        output "ERROR" "Firewalld 规则重载失败" "" "true"
        return 1
    fi

    output "SUCCESS" "已清空所有封禁 IP 并清理 drop 区域配置" "" "true"
}

export_ips() {
    local timestamp export_file sources_ipv4 sources_ipv6
    if ! firewall-cmd --permanent --get-ipsets | grep -qw "$IPSET_NAME_IPV4" && ! firewall-cmd --permanent --get-ipsets | grep -qw "$IPSET_NAME_IPV6"; then
        output "INFO" "无封禁的 IP 或 IPSet 未配置" "" "true"
        return
    fi
    timestamp=$(date +%Y%m%d_%H%M%S)
    export_file="/etc/firewalld/ipthreat_export_$timestamp.txt"
    sources_ipv4=$(firewall-cmd --permanent --ipset="$IPSET_NAME_IPV4" --get-entries)
    sources_ipv6=$(firewall-cmd --permanent --ipset="$IPSET_NAME_IPV6" --get-entries)

    if [[ -z "$sources_ipv4" && -z "$sources_ipv6" ]]; then
        output "INFO" "当前无 IP 封禁列表可导出" "" "true"
        return
    fi

    : > "$export_file"
    [[ -n "$sources_ipv4" ]] && echo "# IPv4 IPs" >> "$export_file" && echo "$sources_ipv4" | tr ' ' '\n' >> "$export_file"
    [[ -n "$sources_ipv6" ]] && echo "# IPv6 IPs" >> "$export_file" && echo "$sources_ipv6" | tr ' ' '\n' >> "$export_file"
    output "SUCCESS" "IP 封禁列表已导出至: $export_file" "" "true"
}

enable_auto_update() {
    local temp_cron cron_schedule input_level
    setup_ipset
    # 设置威胁等级
    output "INFO" "威胁等级说明：数值越大，IP 攻击频率越高，危险性越大，封禁 IP 数量越少，防护范围较窄；数值越小，攻击频率较低，封禁 IP 数量越多，防护范围较广。低数值仍能有效防护潜在威胁。" "" "true"
    output "ACTION" "请输入威胁等级（0~100，数值越高，IP 越危险，数量越少，默认为 50）：" "" "true"
    read -r input_level
    if [[ -z "$input_level" ]]; then
        THREAT_LEVEL=50
        output "INFO" "使用默认威胁等级: $THREAT_LEVEL" "" "true"
    elif [[ ! $input_level =~ ^[0-9]+$ ]] || [[ $input_level -lt 0 ]] || [[ $input_level -gt 100 ]]; then
        output "ERROR" "无效的威胁等级：$input_level，必须在 0~100 之间" "" "true"
        return 1
    else
        THREAT_LEVEL=$input_level
        output "INFO" "威胁等级设置为: $THREAT_LEVEL" "" "true"
    fi
    echo "THREAT_LEVEL=$THREAT_LEVEL" > "$CONFIG_FILE"
    IPTHREAT_URL="https://lists.ipthreat.net/file/ipthreat-lists/threat/threat-${THREAT_LEVEL}.txt.gz"
    TEMP_GZ=$(mktemp /tmp/threat-${THREAT_LEVEL}.XXXXXX.gz)
    TEMP_TXT=$(mktemp /tmp/threat-${THREAT_LEVEL}.XXXXXX.txt)

    if ! update_ips; then
        output "ERROR" "IP 列表更新失败，取消定时任务" "" "true"
        return 1
    fi

    output "ACTION" "请输入定时更新 Cron 规则（例如 '0 0 * * *' 表示每天 00:00，留空使用默认每天 00:00）：" "" "true"
    read -r cron_schedule
    if [[ -z "$cron_schedule" ]]; then
        cron_schedule="0 0 * * *"
        output "INFO" "使用默认定时规则: $cron_schedule" "" "true"
    else
        if ! echo "$cron_schedule" | grep -qE '^[0-9*/,-]+[[:space:]]+[0-9*/,-]+[[:space:]]+[0-9*/,-]+[[:space:]]+[0-9*/,-]+[[:space:]]+[0-9*/,-]+$'; then
            output "ERROR" "无效的 Cron 定时规则: $cron_schedule" "" "true"
            return 1
        fi
        output "INFO" "使用自定义定时规则: $cron_schedule" "" "true"
    fi

    cp "$0" "$CRON_SCRIPT_PATH"
    chmod +x "$CRON_SCRIPT_PATH"

    temp_cron=$(mktemp)
    crontab -l > "$temp_cron" 2>/dev/null || true
    sed -i '/# IPThreat Firewalld Update/d' "$temp_cron"
    echo "$cron_schedule /bin/bash $CRON_SCRIPT_PATH --auto-update # IPThreat Firewalld Update" >> "$temp_cron"
    crontab "$temp_cron"
    rm -f "$temp_cron"
    output "SUCCESS" "已启用定时更新 IP 封禁（规则: $cron_schedule，威胁等级: $THREAT_LEVEL）" "" "true"
}

enable_auto_cleanup() {
    local temp_cron cleanup_schedule

    output "ACTION" "请输入定时清空 IP 封禁的 Cron 规则（例如 '0 0 1 * *' 表示每月第一天 00:00，留空使用默认每月第一天 00:00）：" "" "true"
    read -r cleanup_schedule
    if [[ -z "$cleanup_schedule" ]]; then
        cleanup_schedule="0 0 1 * *"
        output "INFO" "使用默认清空规则: $cleanup_schedule" "" "true"
    else
        if ! echo "$cleanup_schedule" | grep -qE '^[0-9*/,-]+[[:space:]]+[0-9*/,-]+[[:space:]]+[0-9*/,-]+[[:space:]]+[0-9*/,-]+[[:space:]]+[0-9*/,-]+$'; then
            output "ERROR" "无效的 Cron 定时规则: $cleanup_schedule" "" "true"
            return 1
        fi
        output "INFO" "使用自定义清空规则: $cleanup_schedule" "" "true"
    fi

    cp "$0" "$CRON_SCRIPT_PATH"
    chmod +x "$CRON_SCRIPT_PATH"

    temp_cron=$(mktemp)
    crontab -l > "$temp_cron" 2>/dev/null || true
    sed -i '/# IPThreat Firewalld Cleanup/d' "$temp_cron"
    echo "$cleanup_schedule /bin/bash $CRON_SCRIPT_PATH --cleanup # IPThreat Firewalld Cleanup" >> "$temp_cron"
    crontab "$temp_cron"
    rm -f "$temp_cron"
    echo "CLEANUP_SCHEDULE=\"$cleanup_schedule\"" >> "$CONFIG_FILE"
    output "SUCCESS" "已启用定时清空 IP 封禁（规则: $cleanup_schedule）" "" "true"
}

disable_auto_update() {
    local temp_cron
    temp_cron=$(mktemp)
    crontab -l > "$temp_cron" 2>/dev/null || true
    sed -i '/# IPThreat Firewalld Update/d' "$temp_cron"
    crontab "$temp_cron"
    rm -f "$temp_cron"

    # 检查是否还有定时清空任务
    if ! crontab -l 2>/dev/null | grep -q "# IPThreat Firewalld Cleanup"; then
        if [[ -f "$CRON_SCRIPT_PATH" ]]; then
            rm -f "$CRON_SCRIPT_PATH"
            output "INFO" "已删除脚本文件: $CRON_SCRIPT_PATH" "" "true"
        fi
        if [[ -f "$CONFIG_FILE" ]]; then
            rm -f "$CONFIG_FILE"
            output "INFO" "已删除配置文件: $CONFIG_FILE" "" "true"
        fi
    fi
    output "SUCCESS" "已禁用定时更新 IP 封禁" "" "true"
}

disable_auto_cleanup() {
    local temp_cron
    temp_cron=$(mktemp)
    crontab -l > "$temp_cron" 2>/dev/null || true
    sed -i '/# IPThreat Firewalld Cleanup/d' "$temp_cron"
    crontab "$temp_cron"
    rm -f "$temp_cron"
    sed -i '/CLEANUP_SCHEDULE/d' "$CONFIG_FILE"

    # 检查是否还有定时更新任务
    if ! crontab -l 2>/dev/null | grep -q "# IPThreat Firewalld Update"; then
        if [[ -f "$CRON_SCRIPT_PATH" ]]; then
            rm -f "$CRON_SCRIPT_PATH"
            output "INFO" "已删除脚本文件: $CRON_SCRIPT_PATH" "" "true"
        fi
        if [[ -f "$CONFIG_FILE" ]]; then
            rm -f "$CONFIG_FILE"
            output "INFO" "已删除配置文件: $CONFIG_FILE" "" "true"
        fi
    fi
    output "SUCCESS" "已禁用定时清空 IP 封禁" "" "true"
}

view_cron_jobs() {
    local has_jobs=0
    if crontab -l 2>/dev/null | grep -q "# IPThreat Firewalld Update"; then
        output "INFO" "当前定时更新 IP 封禁任务：" "" "true"
        crontab -l 2>/dev/null | grep "# IPThreat Firewalld Update"
        has_jobs=1
    fi
    if crontab -l 2>/dev/null | grep -q "# IPThreat Firewalld Cleanup"; then
        output "INFO" "当前定时清空 IP 封禁任务：" "" "true"
        crontab -l 2>/dev/null | grep "# IPThreat Firewalld Cleanup"
        has_jobs=1
    fi
    if [[ $has_jobs -eq 0 ]]; then
        output "INFO" "无定时任务" "" "true"
    fi
}

update_ips() {
    download_ipthreat_list && filter_and_add_ips
}

show_menu() {
    echo -e "${COLORS[WHITE]}Firewalld IP 封禁管理工具${COLORS[RESET]}"
    echo "封禁工作区域: $ZONE (Firewalld 区域，用于丢弃 IP 流量)"
    echo "当前威胁等级: $THREAT_LEVEL (0~100，数值越高，IP 越危险，数量越少)"
    echo "封禁 IP 使用量: $(get_ipset_usage)"
    echo "---------------------"
    echo "1. 启用定时更新    - 定时下载威胁情报并更新封禁列表"
    echo "2. 禁用定时更新    - 停止定时更新 IP 封禁"
    echo "3. 启用定时清空    - 定时清空所有封禁的 IP"
    echo "4. 禁用定时清空    - 停止定时清空 IP 封禁"
    echo "5. 查看定时任务    - 显示更新和清空任务的定时规则"
    echo "6. 手动封禁 IP     - 手动输入 IP 或范围进行封禁"
    echo "7. 手动解除 IP     - 手动输入 IP 或范围解除封禁"
    echo "8. 清空封禁列表    - 立即清空所有封禁的 IP"
    echo "9. 导出封禁列表    - 将当前封禁的 IP 导出到文件"
    echo "0. 退出            - 退出脚本"
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
        9) export_ips ;;
        *) output "ERROR" "无效选项: $choice" "" "true" ;;
    esac
}

main() {
    local auto_update=0 cleanup=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --auto-update) auto_update=1 ;;
            --cleanup) cleanup=1 ;;
        esac
        shift
    done

    check_dependencies
    select_zone

    if [[ $auto_update -eq 1 ]]; then
        setup_ipset
        update_ips
    elif [[ $cleanup -eq 1 ]]; then
        remove_all_ips
    else
        while true; do
            show_menu
        done
    fi
}

main "$@"
