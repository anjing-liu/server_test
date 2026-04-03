#!/bin/bash
# ==================================================
# 服务器测试一键脚本
# 版本：3.3 - 智能跳过已安装依赖
# 功能：系统信息收集、性能测试、网络测试
# ==================================================

# 颜色定义
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
PLAIN='\033[0m'

# 开始计时
START_TIME=$(date +%s)

# 检查是否为root用户
[[ $EUID -ne 0 ]] && echo -e "${YELLOW}错误：请使用 root 用户运行此脚本${PLAIN}" && exit 1

set +e

# --------------------------------------------------
# 1. 安装依赖（智能跳过已安装）
# --------------------------------------------------
echo -e "${YELLOW}正在检查并安装依赖包...${PLAIN}"
echo ""

if command -v apt &>/dev/null; then
    echo -e "${BLUE}[包管理器] 检测到 Debian/Ubuntu 系统${PLAIN}"
    
    if [ ! -f /tmp/apt_updated ]; then
        echo -e "${BLUE}[包管理器] 正在更新软件源...${PLAIN}"
        apt update -y >/dev/null 2>&1
        touch /tmp/apt_updated
        echo -e "${GREEN}[包管理器] 软件源更新完成${PLAIN}"
    fi
    
    # 基础包
    for pkg in iperf3 mtr sysbench tar curl bc wget git vim net-tools dnsutils ethtool tcpdump nmap htop nmon lsof rsync pciutils usbutils ioping fio zip unzip bzip2 screen tmux jq tree; do
        if dpkg -l | grep -q "^ii  $pkg "; then
            echo -e "${GREEN}[已安装] $pkg${PLAIN}"
        else
            echo -e "${BLUE}[正在安装] $pkg${PLAIN}"
            apt install -y $pkg >/dev/null 2>&1
        fi
    done
    
    # 开发工具包
    for pkg in build-essential cmake python3 python3-pip silversearcher-ag; do
        if dpkg -l | grep -q "^ii  $pkg "; then
            echo -e "${GREEN}[已安装] $pkg${PLAIN}"
        else
            echo -e "${BLUE}[正在安装] $pkg${PLAIN}"
            apt install -y $pkg >/dev/null 2>&1
        fi
    done
    
elif command -v yum &>/dev/null; then
    echo -e "${BLUE}[包管理器] 检测到 CentOS/RHEL 7 系统${PLAIN}"
    
    if [ ! -f /tmp/epel_installed ]; then
        echo -e "${BLUE}[包管理器] 正在启用 EPEL 源...${PLAIN}"
        yum install -y epel-release >/dev/null 2>&1
        touch /tmp/epel_installed
    fi
    
    for pkg in iperf3 mtr sysbench tar curl bc wget git vim net-tools bind-utils ethtool tcpdump nmap htop nmon lsof rsync pciutils usbutils ioping fio zip unzip bzip2 screen tmux jq tree gcc gcc-c++ make cmake python3 python3-pip; do
        if rpm -q $pkg >/dev/null 2>&1; then
            echo -e "${GREEN}[已安装] $pkg${PLAIN}"
        else
            echo -e "${BLUE}[正在安装] $pkg${PLAIN}"
            yum install -y $pkg >/dev/null 2>&1
        fi
    done
    
elif command -v dnf &>/dev/null; then
    echo -e "${BLUE}[包管理器] 检测到 CentOS/RHEL 8+ 系统${PLAIN}"
    
    if [ ! -f /tmp/epel_installed ]; then
        echo -e "${BLUE}[包管理器] 正在启用 EPEL 源...${PLAIN}"
        dnf install -y epel-release >/dev/null 2>&1
        touch /tmp/epel_installed
    fi
    
    for pkg in iperf3 mtr sysbench tar curl bc wget git vim net-tools bind-utils ethtool tcpdump nmap htop nmon lsof rsync pciutils usbutils ioping fio zip unzip bzip2 screen tmux jq tree gcc gcc-c++ make cmake python3 python3-pip; do
        if rpm -q $pkg >/dev/null 2>&1; then
            echo -e "${GREEN}[已安装] $pkg${PLAIN}"
        else
            echo -e "${BLUE}[正在安装] $pkg${PLAIN}"
            dnf install -y $pkg >/dev/null 2>&1
        fi
    done
    
elif command -v pacman &>/dev/null; then
    echo -e "${BLUE}[包管理器] 检测到 Arch Linux 系统${PLAIN}"
    echo -e "${BLUE}[包管理器] 正在同步软件源...${PLAIN}"
    pacman -Sy --noconfirm >/dev/null 2>&1
    pacman -S --noconfirm iperf3 mtr sysbench tar curl bc wget git vim net-tools dnsutils ethtool tcpdump nmap htop nmon lsof rsync pciutils usbutils ioping fio base-devel cmake python python-pip zip unzip bzip2 screen tmux jq tree the_silver_searcher >/dev/null 2>&1
    
elif command -v apk &>/dev/null; then
    echo -e "${BLUE}[包管理器] 检测到 Alpine Linux 系统${PLAIN}"
    echo -e "${BLUE}[包管理器] 正在更新软件源...${PLAIN}"
    apk update >/dev/null 2>&1
    apk add iperf3 mtr sysbench tar curl bc wget git vim net-tools bind-tools ethtool tcpdump nmap htop nmon lsof rsync pciutils usbutils ioping fio gcc g++ make cmake python3 py3-pip zip unzip bzip2 screen tmux jq tree the_silver_searcher >/dev/null 2>&1
fi

echo -e "${GREEN}依赖包检查完成${PLAIN}"
echo ""

# --------------------------------------------------
# 2. 设置主机名（自动检测并修改）
# --------------------------------------------------
CURRENT_HOSTNAME=$(hostname)
EXPECTED_HOSTNAME="www.1373737.xyz"
if [[ "$CURRENT_HOSTNAME" != "$EXPECTED_HOSTNAME" ]]; then
    echo -e "${BLUE}检测到主机名为: $CURRENT_HOSTNAME${PLAIN}"
    echo -e "${BLUE}正在修改主机名为: $EXPECTED_HOSTNAME${PLAIN}"
    hostnamectl set-hostname "$EXPECTED_HOSTNAME" >/dev/null 2>&1
    echo "$EXPECTED_HOSTNAME" > /etc/hostname
    sed -i "s/127.0.1.1.*/127.0.1.1 $EXPECTED_HOSTNAME/g" /etc/hosts 2>/dev/null
    echo -e "${GREEN}主机名修改完成${PLAIN}"
else
    echo -e "${GREEN}主机名已经是 $EXPECTED_HOSTNAME${PLAIN}"
fi

# 重新获取主机名
HOSTNAME=$(hostname)
echo ""

# --------------------------------------------------
# 3. 开启 BBR（静默）
# --------------------------------------------------
if ! lsmod | grep -q bbr; then
    modprobe tcp_bbr 2>/dev/null
    echo "tcp_bbr" >> /etc/modules-load.d/modules.conf 2>/dev/null
fi
grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf || echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf || echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
sysctl -p >/dev/null 2>&1

# --------------------------------------------------
# 4. 系统信息收集
# --------------------------------------------------
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_VERSION="$PRETTY_NAME"
else
    OS_VERSION="Unknown"
fi

KERNEL_VER=$(uname -r)
ARCH=$(uname -m)

if command -v lscpu &>/dev/null; then
    CPU_MODEL=$(lscpu | grep "Model name" | awk -F':' '{print $2}' | xargs)
    [ -z "$CPU_MODEL" ] && CPU_MODEL=$(lscpu | grep "型号名称" | awk -F':' '{print $2}' | xargs)
else
    CPU_MODEL=$(cat /proc/cpuinfo | grep "model name" | head -1 | awk -F':' '{print $2}' | xargs)
fi

CPU_CORES=$(nproc)

if command -v lscpu &>/dev/null; then
    CPU_FREQ=$(lscpu | grep "CPU MHz" | awk -F':' '{print $2}' | xargs | cut -d'.' -f1)
    [ -z "$CPU_FREQ" ] && CPU_FREQ=$(lscpu | grep "CPU动态频率" | awk -F':' '{print $2}' | xargs | cut -d'.' -f1)
else
    CPU_FREQ=$(cat /proc/cpuinfo | grep "cpu MHz" | head -1 | awk -F':' '{print $2}' | xargs | cut -d'.' -f1)
fi
[ -z "$CPU_FREQ" ] && CPU_FREQ="未知"

CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
if [ -z "$CPU_USAGE" ]; then
    CPU_USAGE=$(top -bn1 | grep "%Cpu" | awk '{print $2}')
fi
[ -z "$CPU_USAGE" ] && CPU_USAGE=0

LOAD_AVG=$(cat /proc/loadavg | awk '{print $1","$2","$3}')

MEM_TOTAL=$(free -m | awk '/^Mem:/{print $2}')
MEM_USED=$(free -m | awk '/^Mem:/{print $3}')
MEM_PERCENT=$(echo "scale=2; $MEM_USED*100/$MEM_TOTAL" | bc)
MEM_INFO="${MEM_USED}.00/${MEM_TOTAL}.00 MB (${MEM_PERCENT}%)"

SWAP_TOTAL=$(free -m | awk '/^Swap:/{print $2}')
if [ -z "$SWAP_TOTAL" ] || [ "$SWAP_TOTAL" -eq 0 ]; then
    SWAP_INFO="0.00/0.00 MB (0.00%)"
else
    SWAP_USED=$(free -m | awk '/^Swap:/{print $3}')
    SWAP_PERCENT=$(echo "scale=2; $SWAP_USED*100/$SWAP_TOTAL" | bc)
    SWAP_INFO="${SWAP_USED}.00/${SWAP_TOTAL}.00 MB (${SWAP_PERCENT}%)"
fi

DISK_TOTAL=$(df -BG / | awk 'NR==2{print $2}' | sed 's/G//')
DISK_USED=$(df -BG / | awk 'NR==2{print $3}' | sed 's/G//')
DISK_PERCENT=$(df -h / | awk 'NR==2{print $5}' | sed 's/%//')
DISK_INFO="${DISK_USED}G/${DISK_TOTAL}G (${DISK_PERCENT}%)"

RX_BYTES=0
TX_BYTES=0
for netdev in $(ls /sys/class/net/ 2>/dev/null | grep -v lo); do
    rx=$(cat /sys/class/net/$netdev/statistics/rx_bytes 2>/dev/null)
    tx=$(cat /sys/class/net/$netdev/statistics/tx_bytes 2>/dev/null)
    RX_BYTES=$((RX_BYTES + rx))
    TX_BYTES=$((TX_BYTES + tx))
done
RX_GB=$(echo "scale=2; $RX_BYTES/1024/1024/1024" | bc)
TX_GB=$(echo "scale=2; $TX_BYTES/1024/1024/1024" | bc)
[ -z "$RX_GB" ] && RX_GB=0
[ -z "$TX_GB" ] && TX_GB=0

TCP_ALGO=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
[ -z "$TCP_ALGO" ] && TCP_ALGO="未知"

IPV4=$(curl -s4m5 ifconfig.co 2>/dev/null || curl -s4m5 icanhazip.com 2>/dev/null || curl -s4m5 ipinfo.io/ip 2>/dev/null)
[ -z "$IPV4" ] && IPV4="未知"

ISP=$(curl -s4m5 ipinfo.io/org 2>/dev/null | cut -d' ' -f2- | head -n1)
GEO_CITY=$(curl -s4m5 ipinfo.io/city 2>/dev/null)
GEO_COUNTRY=$(curl -s4m5 ipinfo.io/country 2>/dev/null)
[ -z "$ISP" ] && ISP="未知"
[ -z "$GEO_CITY" ] && GEO_CITY="Unknown"
[ -z "$GEO_COUNTRY" ] && GEO_COUNTRY="Unknown"
GEO="${GEO_CITY}, ${GEO_COUNTRY}"

DNS1=$(grep -m1 nameserver /etc/resolv.conf 2>/dev/null | awk '{print $2}')
DNS2=$(grep -m2 nameserver /etc/resolv.conf 2>/dev/null | tail -n1 | awk '{print $2}')
[ -z "$DNS1" ] && DNS1="未知"
[ -z "$DNS2" ] && DNS2="无"

CURRENT_TIME=$(TZ='Asia/Shanghai' date "+%Y-%m-%d %H:%M %p" 2>/dev/null)

UPTIME_SEC=$(cat /proc/uptime 2>/dev/null | awk '{print $1}')
if [ -n "$UPTIME_SEC" ]; then
    DAYS=$(echo "$UPTIME_SEC/86400" | bc)
    HOURS=$(echo "($UPTIME_SEC%86400)/3600" | bc)
    MINUTES=$(echo "($UPTIME_SEC%3600)/60" | bc)
    UPTIME_STR="${DAYS}天 ${HOURS}时 ${MINUTES}分"
else
    UPTIME_STR="未知"
fi

# --------------------------------------------------
# 5. 性能基准测试
# --------------------------------------------------
SINGLE_SCORE=$(sysbench cpu --cpu-max-prime=20000 --threads=1 --time=10 run 2>/dev/null | grep "events per second" | awk '{print $4}')
if [ -n "$SINGLE_SCORE" ]; then
    SINGLE_SCORE=$(echo "$SINGLE_SCORE * 10" | bc | cut -d'.' -f1)
else
    SINGLE_SCORE=0
fi

MULTI_SCORE=$(sysbench cpu --cpu-max-prime=20000 --threads=$CPU_CORES --time=10 run 2>/dev/null | grep "events per second" | awk '{print $4}')
if [ -n "$MULTI_SCORE" ]; then
    MULTI_SCORE=$(echo "$MULTI_SCORE * 10" | bc | cut -d'.' -f1)
else
    MULTI_SCORE=0
fi

MEM_READ=$(sysbench memory --memory-block-size=1M --memory-total-size=10G --memory-oper=read run 2>/dev/null | grep "transferred" | awk '{print $4}' | head -n1)
[ -z "$MEM_READ" ] && MEM_READ="0"

MEM_WRITE=$(sysbench memory --memory-block-size=1M --memory-total-size=10G --memory-oper=write run 2>/dev/null | grep "transferred" | awk '{print $4}' | head -n1)
[ -z "$MEM_WRITE" ] && MEM_WRITE="0"

# --------------------------------------------------
# 6. 硬盘 I/O 性能测试
# --------------------------------------------------
ROTATIONAL=$(cat /sys/block/$(lsblk -no pkname $(df / | tail -1 | cut -d' ' -f1) 2>/dev/null | head -1)/queue/rotational 2>/dev/null)
if [ "$ROTATIONAL" -eq 0 ]; then
    DISK_TYPE="SSD"
elif [ "$ROTATIONAL" -eq 1 ]; then
    DISK_TYPE="HDD"
else
    DISK_TYPE="未知"
fi

IO_SPEEDS=()
for i in {1..3}; do
    SPEED=$(dd if=/dev/zero of=/tmp/test_io bs=1M count=1024 conv=fdatasync 2>&1 | grep -oP '\d+(\.\d+)? MB/s' | head -1 | sed 's/ MB\/s//')
    if [ -n "$SPEED" ]; then
        IO_SPEEDS+=($SPEED)
    else
        IO_SPEEDS+=(0)
    fi
    rm -f /tmp/test_io 2>/dev/null
    sleep 1
done
AVG_SPEED=$(echo "scale=2; (${IO_SPEEDS[0]}+${IO_SPEEDS[1]}+${IO_SPEEDS[2]})/3" | bc)

if (( $(echo "$AVG_SPEED < 100" | bc -l) )); then
    LEVEL="一般"
elif (( $(echo "$AVG_SPEED < 200" | bc -l) )); then
    LEVEL="中等"
elif (( $(echo "$AVG_SPEED < 500" | bc -l) )); then
    LEVEL="良好"
else
    LEVEL="优秀"
fi

# --------------------------------------------------
# 7. 输出系统信息
# --------------------------------------------------
echo -e "${YELLOW}系统信息查询${PLAIN}"
echo ""
echo "主机名：              ${HOSTNAME}"
echo "系统版本：            ${OS_VERSION}"
echo "Linux版本：           ${KERNEL_VER}"
echo "CPU架构：             ${ARCH}"
echo "CPU型号：             ${CPU_MODEL}"
echo "CPU核心数：           ${CPU_CORES}"
echo "CPU频率：             ${CPU_FREQ} GHz"
echo "CPU占用：             ${CPU_USAGE}%"
echo "系统负载：            ${LOAD_AVG}"
echo "物理内存：            ${MEM_INFO}"
echo "虚拟内存：            ${SWAP_INFO}"
echo "硬盘占用：            ${DISK_INFO}"
echo "总接收：              ${RX_GB} GB"
echo "总发送：              ${TX_GB} GB"
echo "网络算法：            ${TCP_ALGO}"
echo "运营商：              ${ISP}"
echo "IPv4地址：            ${IPV4}"
echo "DNS地址：             ${DNS1} ${DNS2}"
echo "地理位置：            ${GEO}"
echo "系统时间：            ${CURRENT_TIME}"
echo ""
echo -e "${YELLOW}系统性能基准测试结果${PLAIN}"
echo ""
echo "1线程测试（单核）得分：          ${SINGLE_SCORE} Scores"
echo "${CPU_CORES}线程测试（多核）得分：          ${MULTI_SCORE} Scores"
echo "============================="
echo "内存读测试：                     ${MEM_READ} MB/s"
echo "内存写测试：                     ${MEM_WRITE} MB/s"
echo "============================="
echo "系统运行时长：                   ${UPTIME_STR}"
echo ""
echo -e "${YELLOW}硬盘 I/O 性能测试${PLAIN}"
echo ""
echo "硬盘性能测试正在进行中..."
echo ""
echo "硬盘性能测试结果如下："
echo -e "硬盘I/O（第一次测试）：          ${YELLOW}${IO_SPEEDS[0]} MB/s${PLAIN}"
echo -e "硬盘I/O（第二次测试）：          ${YELLOW}${IO_SPEEDS[1]} MB/s${PLAIN}"
echo -e "硬盘I/O（第三次测试）：          ${YELLOW}${IO_SPEEDS[2]} MB/s${PLAIN}"
echo -e "硬盘I/O（平均测试）：            ${YELLOW}${AVG_SPEED} MB/s${PLAIN}"
echo "硬盘类型：                      ${DISK_TYPE}"
echo "硬盘性能等级：                  ${LEVEL}"
echo -e "${GREEN}测试数据不是百分百准确，以官方宣称为主。${PLAIN}"
echo ""

# --------------------------------------------------
# 8. 执行外部测试脚本
# --------------------------------------------------
bash <(curl -Ls https://IP.Check.Place) 2>/dev/null
echo ""

curl -s https://raw.githubusercontent.com/zhanghanyun/backtrace/main/install.sh | sh 2>/dev/null
curl -s https://raw.githubusercontent.com/anjing-liu/mtr_trace/main/mtr_trace.sh | bash 2>/dev/null
echo ""

echo "2" | bash <(curl -sL https://raw.githubusercontent.com/i-abc/Speedtest/main/speedtest.sh) 2>/dev/null
echo ""

echo "" | bash <(curl -L -s check.unlock.media) 2>/dev/null
echo ""

printf "1\n8\n" | nexttrace --fast-trace 2>/dev/null
echo ""

bash <(curl -Ls https://Net.Check.Place) -R 2>/dev/null
echo ""

wget -qO- bench.sh | bash 2>/dev/null
echo ""

wget --no-check-certificate -O memoryCheck.sh https://raw.githubusercontent.com/uselibrary/memoryCheck/main/memoryCheck.sh 2>/dev/null && chmod +x memoryCheck.sh && bash memoryCheck.sh 2>/dev/null
rm -f memoryCheck.sh 2>/dev/null
echo ""

# --------------------------------------------------
# 9. 总耗时统计
# --------------------------------------------------
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
HOURS_ELAPSED=$((ELAPSED / 3600))
MINUTES_ELAPSED=$(((ELAPSED % 3600) / 60))
SECONDS_ELAPSED=$((ELAPSED % 60))

echo "所有测试完成！总耗时: ${HOURS_ELAPSED}小时 ${MINUTES_ELAPSED}分钟 ${SECONDS_ELAPSED}秒"
