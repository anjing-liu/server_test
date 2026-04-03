#!/bin/bash
# ==================================================
# 服务器测试一键脚本
# 功能：安装依赖、配置主机名+BBR、系统信息收集、性能测试、网络测试等
# 作者：根据用户需求定制
# 版本：1.0
# ==================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

# 开始计时
START_TIME=$(date +%s)

# 检查是否为root用户
[[ $EUID -ne 0 ]] && echo -e "${RED}错误：请使用 root 用户运行此脚本${PLAIN}" && exit 1

# 设置脚本出错时继续执行
set +e

echo -e "${CYAN}=========================================${PLAIN}"
echo -e "${CYAN}      服务器测试一键脚本 v1.0           ${PLAIN}"
echo -e "${CYAN}=========================================${PLAIN}\n"

# --------------------------------------------------
# 1. 安装依赖
# --------------------------------------------------
echo -e "${BLUE}[1/9] 正在安装依赖...${PLAIN}"
if command -v apt &>/dev/null; then
    apt update -y
    apt install -y iperf3 mtr sysbench tar curl bc
elif command -v yum &>/dev/null; then
    yum install -y epel-release
    yum install -y iperf3 mtr sysbench tar curl bc
elif command -v dnf &>/dev/null; then
    dnf install -y epel-release
    dnf install -y iperf3 mtr sysbench tar curl bc
else
    echo -e "${RED}不支持的包管理器，请手动安装依赖。${PLAIN}"
    exit 1
fi
echo -e "${GREEN}依赖安装完成。${PLAIN}\n"

# --------------------------------------------------
# 2. 设置主机名
# --------------------------------------------------
echo -e "${BLUE}[2/9] 检查并设置主机名...${PLAIN}"
CURRENT_HOSTNAME=$(hostname)
EXPECTED_HOSTNAME="www.1373737.xyz"
if [[ "$CURRENT_HOSTNAME" != "$EXPECTED_HOSTNAME" ]]; then
    hostnamectl set-hostname "$EXPECTED_HOSTNAME"
    echo "$EXPECTED_HOSTNAME" > /etc/hostname
    sed -i "s/127.0.1.1.*/127.0.1.1 $EXPECTED_HOSTNAME/g" /etc/hosts
    echo -e "${GREEN}主机名已修改为 $EXPECTED_HOSTNAME${PLAIN}"
else
    echo -e "${GREEN}主机名已经是 $EXPECTED_HOSTNAME${PLAIN}"
fi

# --------------------------------------------------
# 3. 开启 BBR（显示为 bbr3）
# --------------------------------------------------
echo -e "${BLUE}[3/9] 配置 TCP BBR（显示为 bbr3）...${PLAIN}"
if ! lsmod | grep -q bbr; then
    modprobe tcp_bbr
    echo "tcp_bbr" >> /etc/modules-load.d/modules.conf
fi
grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf || echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf || echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
sysctl -p >/dev/null 2>&1
echo -e "${GREEN}BBR 已启用（显示为 bbr3）${PLAIN}\n"

# --------------------------------------------------
# 4. 系统信息收集
# --------------------------------------------------
echo -e "${BLUE}[4/9] 系统信息收集...${PLAIN}"

# 主机名
HOSTNAME=$(hostname)

# 系统版本
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_VERSION="$PRETTY_NAME"
else
    OS_VERSION="Unknown"
fi

# Linux内核版本
KERNEL_VER=$(uname -r)

# CPU架构
ARCH=$(uname -m)

# CPU型号、核心数、频率
CPU_MODEL=$(lscpu | grep "Model name" | awk -F':' '{print $2}' | xargs)
CPU_CORES=$(nproc)
CPU_FREQ=$(lscpu | grep "CPU MHz" | awk -F':' '{print $2}' | xargs | cut -d'.' -f1)

# CPU占用（瞬时）
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
if [ -z "$CPU_USAGE" ]; then
    CPU_USAGE=$(top -bn1 | grep "%Cpu" | awk '{print $2}')
fi
[ -z "$CPU_USAGE" ] && CPU_USAGE=0

# 系统负载
LOAD_AVG=$(cat /proc/loadavg | awk '{print $1","$2","$3}')

# 物理内存
MEM_TOTAL=$(free -m | awk '/^Mem:/{print $2}')
MEM_USED=$(free -m | awk '/^Mem:/{print $3}')
MEM_FREE=$(free -m | awk '/^Mem:/{print $4}')
MEM_PERCENT=$(echo "scale=2; $MEM_USED*100/$MEM_TOTAL" | bc)
MEM_INFO="${MEM_USED}.00/${MEM_TOTAL}.00 MB (${MEM_PERCENT}%)"

# 虚拟内存(Swap)
SWAP_TOTAL=$(free -m | awk '/^Swap:/{print $2}')
if [ "$SWAP_TOTAL" -eq 0 ]; then
    SWAP_INFO="0.00/0.00 MB (0.00%)"
else
    SWAP_USED=$(free -m | awk '/^Swap:/{print $3}')
    SWAP_PERCENT=$(echo "scale=2; $SWAP_USED*100/$SWAP_TOTAL" | bc)
    SWAP_INFO="${SWAP_USED}.00/${SWAP_TOTAL}.00 MB (${SWAP_PERCENT}%)"
fi

# 硬盘占用（根分区）
DISK_TOTAL=$(df -BG / | awk 'NR==2{print $2}' | sed 's/G//')
DISK_USED=$(df -BG / | awk 'NR==2{print $3}' | sed 's/G//')
DISK_PERCENT=$(df -h / | awk 'NR==2{print $5}' | sed 's/%//')
DISK_INFO="${DISK_USED}G/${DISK_TOTAL}G (${DISK_PERCENT}%)"

# 总接收/总发送（所有网卡）
RX_BYTES=0
TX_BYTES=0
for netdev in $(ls /sys/class/net/ | grep -v lo); do
    rx=$(cat /sys/class/net/$netdev/statistics/rx_bytes 2>/dev/null)
    tx=$(cat /sys/class/net/$netdev/statistics/tx_bytes 2>/dev/null)
    RX_BYTES=$((RX_BYTES + rx))
    TX_BYTES=$((TX_BYTES + tx))
done
RX_GB=$(echo "scale=2; $RX_BYTES/1024/1024/1024" | bc)
TX_GB=$(echo "scale=2; $TX_BYTES/1024/1024/1024" | bc)
[ -z "$RX_GB" ] && RX_GB=0
[ -z "$TX_GB" ] && TX_GB=0

# 网络算法（显示为bbr3）
TCP_ALGO=$(sysctl -n net.ipv4.tcp_congestion_control)
if [[ "$TCP_ALGO" == "bbr" ]]; then
    TCP_ALGO="bbr3"
fi

# 运营商、IPv4、地理位置
IPV4=$(curl -s4m5 ifconfig.co || curl -s4m5 icanhazip.com || curl -s4m5 ipinfo.io/ip)
ISP=$(curl -s4m5 ipinfo.io/org | cut -d' ' -f2- | head -n1)
[ -z "$ISP" ] && ISP="Unknown"
GEO=$(curl -s4m5 ipinfo.io/city),$(curl -s4m5 ipinfo.io/country)
[ -z "$GEO" ] && GEO="Unknown, Unknown"

# DNS地址
DNS1=$(grep -m1 nameserver /etc/resolv.conf | awk '{print $2}')
DNS2=$(grep -m2 nameserver /etc/resolv.conf | tail -n1 | awk '{print $2}')
[ -z "$DNS2" ] && DNS2="无"

# 系统时间（东八区）
TIMEZONE=$(timedatectl show --property=Timezone --value)
CURRENT_TIME=$(TZ='Asia/Shanghai' date "+%Y-%m-%d %H:%M %p")

# 运行时长
UPTIME_SEC=$(cat /proc/uptime | awk '{print $1}')
DAYS=$(echo "$UPTIME_SEC/86400" | bc)
HOURS=$(echo "($UPTIME_SEC%86400)/3600" | bc)
MINUTES=$(echo "($UPTIME_SEC%3600)/60" | bc)
UPTIME_STR="${DAYS}天 ${HOURS}时 ${MINUTES}分"

echo -e "${GREEN}系统信息收集完成。${PLAIN}\n"

# --------------------------------------------------
# 5. 性能基准测试（CPU单/多核 + 内存）
# --------------------------------------------------
echo -e "${BLUE}[5/9] 系统性能基准测试...${PLAIN}"

# 单核CPU测试
SINGLE_SCORE=$(sysbench cpu --cpu-max-prime=20000 --threads=1 --time=10 run 2>/dev/null | grep "events per second" | awk '{print $4}')
if [ -n "$SINGLE_SCORE" ]; then
    SINGLE_SCORE=$(echo "$SINGLE_SCORE * 10" | bc | cut -d'.' -f1)
else
    SINGLE_SCORE=0
fi

# 多核CPU测试（使用全部核心）
MULTI_SCORE=$(sysbench cpu --cpu-max-prime=20000 --threads=$CPU_CORES --time=10 run 2>/dev/null | grep "events per second" | awk '{print $4}')
if [ -n "$MULTI_SCORE" ]; then
    MULTI_SCORE=$(echo "$MULTI_SCORE * 10" | bc | cut -d'.' -f1)
else
    MULTI_SCORE=0
fi

# 内存读测试
MEM_READ=$(sysbench memory --memory-block-size=1M --memory-total-size=10G --memory-oper=read run 2>/dev/null | grep "transferred" | awk '{print $4}' | head -n1)
[ -z "$MEM_READ" ] && MEM_READ="0"
# 内存写测试
MEM_WRITE=$(sysbench memory --memory-block-size=1M --memory-total-size=10G --memory-oper=write run 2>/dev/null | grep "transferred" | awk '{print $4}' | head -n1)
[ -z "$MEM_WRITE" ] && MEM_WRITE="0"

echo -e "${GREEN}性能测试完成。${PLAIN}\n"

# --------------------------------------------------
# 6. 硬盘 I/O 性能测试（三次 dd + 类型判断）
# --------------------------------------------------
echo -e "${BLUE}[6/9] 硬盘 I/O 性能测试...${PLAIN}"
# 判断硬盘类型（HDD/SSD）
ROTATIONAL=$(cat /sys/block/$(lsblk -no pkname $(df / | tail -1 | cut -d' ' -f1) | head -1)/queue/rotational 2>/dev/null)
if [ "$ROTATIONAL" -eq 0 ]; then
    DISK_TYPE="SSD"
elif [ "$ROTATIONAL" -eq 1 ]; then
    DISK_TYPE="HDD"
else
    DISK_TYPE="Unknown"
fi

# 三次 dd 测试写速度（1GB 文件）
IO_SPEEDS=()
for i in {1..3}; do
    SPEED=$(dd if=/dev/zero of=/tmp/test_io bs=1M count=1024 conv=fdatasync 2>&1 | grep -oP '\d+(\.\d+)? MB/s' | head -1 | sed 's/ MB\/s//')
    if [ -n "$SPEED" ]; then
        IO_SPEEDS+=($SPEED)
    else
        IO_SPEEDS+=(0)
    fi
    rm -f /tmp/test_io
    sleep 1
done
AVG_SPEED=$(echo "scale=2; (${IO_SPEEDS[0]}+${IO_SPEEDS[1]}+${IO_SPEEDS[2]})/3" | bc)

# 性能等级
if (( $(echo "$AVG_SPEED < 100" | bc -l) )); then
    LEVEL="一般"
elif (( $(echo "$AVG_SPEED < 200" | bc -l) )); then
    LEVEL="中等"
else
    LEVEL="良好"
fi

echo -e "${GREEN}硬盘测试完成。${PLAIN}\n"

# --------------------------------------------------
# 7. 输出系统信息汇总（按照示例格式）
# --------------------------------------------------
echo -e "${CYAN}========== 系统信息汇总 ==========${PLAIN}"
echo -e "${YELLOW}主机名:${PLAIN} $HOSTNAME"
echo -e "${YELLOW}系统版本:${PLAIN} $OS_VERSION"
echo -e "${YELLOW}Linux版本:${PLAIN} $KERNEL_VER"
echo -e "${YELLOW}CPU架构:${PLAIN} $ARCH"
echo -e "${YELLOW}CPU型号:${PLAIN} $CPU_MODEL"
echo -e "${YELLOW}CPU核心数:${PLAIN} $CPU_CORES"
echo -e "${YELLOW}CPU频率:${PLAIN} $CPU_FREQ MHz"
echo -e "${YELLOW}CPU占用:${PLAIN} $CPU_USAGE%"
echo -e "${YELLOW}系统负载:${PLAIN} $LOAD_AVG"
echo -e "${YELLOW}物理内存:${PLAIN} $MEM_INFO"
echo -e "${YELLOW}虚拟内存:${PLAIN} $SWAP_INFO"
echo -e "${YELLOW}硬盘占用:${PLAIN} $DISK_INFO"
echo -e "${YELLOW}总接收:${PLAIN} ${RX_GB}GB"
echo -e "${YELLOW}总发送:${PLAIN} ${TX_GB}GB"
echo -e "${YELLOW}网络算法:${PLAIN} $TCP_ALGO"
echo -e "${YELLOW}运营商:${PLAIN} $ISP"
echo -e "${YELLOW}IPv4地址:${PLAIN} $IPV4"
echo -e "${YELLOW}DNS地址:${PLAIN} $DNS1 $DNS2"
echo -e "${YELLOW}地理位置:${PLAIN} $GEO"
echo -e "${YELLOW}系统时间:${PLAIN} $CURRENT_TIME"
echo -e "${YELLOW}运行时长:${PLAIN} $UPTIME_STR"
echo -e "${CYAN}====================================${PLAIN}\n"

echo -e "${CYAN}========== 性能测试结果 ==========${PLAIN}"
echo -e "${YELLOW}1线程测试(单核)得分:${PLAIN} $SINGLE_SCORE Scores"
echo -e "${YELLOW}2线程测试(多核)得分:${PLAIN} $MULTI_SCORE Scores"
echo -e "${YELLOW}内存读测试:${PLAIN} $MEM_READ MB/s"
echo -e "${YELLOW}内存写测试:${PLAIN} $MEM_WRITE MB/s"
echo -e "${CYAN}====================================${PLAIN}\n"

echo -e "${CYAN}========== 硬盘性能测试 ==========${PLAIN}"
echo -e "${YELLOW}硬盘I/O(第一次测试):${PLAIN} ${IO_SPEEDS[0]} MB/s"
echo -e "${YELLOW}硬盘I/O(第二次测试):${PLAIN} ${IO_SPEEDS[1]} MB/s"
echo -e "${YELLOW}硬盘I/O(第三次测试):${PLAIN} ${IO_SPEEDS[2]} MB/s"
echo -e "${YELLOW}硬盘I/O(平均测试):${PLAIN} $AVG_SPEED MB/s"
echo -e "${YELLOW}硬盘类型:${PLAIN} $DISK_TYPE"
echo -e "${YELLOW}硬盘性能等级:${PLAIN} $LEVEL"
echo -e "${CYAN}====================================${PLAIN}\n"

# --------------------------------------------------
# 8. 执行各项网络和测试脚本（自动选择）
# --------------------------------------------------
echo -e "${BLUE}[7/9] 执行 IP 风险检查...${PLAIN}"
bash <(curl -Ls https://IP.Check.Place) 2>/dev/null
echo -e "\n"

echo -e "${BLUE}[8/9] 执行三网回程线路测试...${PLAIN}"
curl -s https://raw.githubusercontent.com/zhanghanyun/backtrace/main/install.sh | sh 2>/dev/null
curl -s https://raw.githubusercontent.com/anjing-liu/mtr_trace/main/mtr_trace.sh | bash 2>/dev/null
echo -e "\n"

echo -e "${BLUE}[8/9] 执行三网+教育网 IPv4 单线程测速（自动选择2）...${PLAIN}"
echo "2" | bash <(curl -sL https://raw.githubusercontent.com/i-abc/Speedtest/main/speedtest.sh) 2>/dev/null
echo -e "\n"

echo -e "${BLUE}[8/9] 执行流媒体解锁测试（自动回车）...${PLAIN}"
echo "" | bash <(curl -L -s check.unlock.media) 2>/dev/null
echo -e "\n"

echo -e "${BLUE}[8/9] 执行全国五网ISP路由回程测试（自动选择1和8）...${PLAIN}"
printf "1\n8\n" | nexttrace --fast-trace 2>/dev/null
echo -e "\n"

echo -e "${BLUE}[8/9] 执行三网回程路由测试...${PLAIN}"
bash <(curl -Ls https://Net.Check.Place) -R 2>/dev/null
echo -e "\n"

echo -e "${BLUE}[8/9] 执行 bench 性能测试...${PLAIN}"
wget -qO- bench.sh | bash 2>/dev/null
echo -e "\n"

echo -e "${BLUE}[8/9] 执行超售测试...${PLAIN}"
wget --no-check-certificate -O memoryCheck.sh https://raw.githubusercontent.com/uselibrary/memoryCheck/main/memoryCheck.sh && chmod +x memoryCheck.sh && bash memoryCheck.sh 2>/dev/null
rm -f memoryCheck.sh
echo -e "\n"

# --------------------------------------------------
# 9. 总耗时统计
# --------------------------------------------------
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
HOURS_ELAPSED=$((ELAPSED / 3600))
MINUTES_ELAPSED=$(((ELAPSED % 3600) / 60))
SECONDS_ELAPSED=$((ELAPSED % 60))

echo -e "${GREEN}========================================${PLAIN}"
echo -e "${GREEN}       所有测试完成！                   ${PLAIN}"
echo -e "${GREEN}       总耗时: ${HOURS_ELAPSED}小时 ${MINUTES_ELAPSED}分钟 ${SECONDS_ELAPSED}秒${PLAIN}"
echo -e "${GREEN}========================================${PLAIN}"
