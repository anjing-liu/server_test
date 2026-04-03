#!/bin/bash
# ==================================================
# 服务器测试一键脚本 v6.1
# 功能：系统信息、性能测试、BBR、外部测试（全自动）
# 兼容：Ubuntu/Debian/CentOS/Rocky/AlmaLinux
# 快捷命令：安装后输入 sn 即可运行
# ==================================================

set -euo pipefail
set +e

# 颜色
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
PLAIN='\033[0m'

START_TIME=$(date +%s)

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}错误：请使用 root 用户运行此脚本${PLAIN}"
    exit 1
fi

# 快捷命令 sn
create_shortcut() {
    local SCRIPT_PATH=$(realpath "$0" 2>/dev/null || readlink -f "$0" 2>/dev/null)
    if [ -f "$SCRIPT_PATH" ]; then
        if [ ! -f /usr/local/bin/sn ]; then
            ln -sf "$SCRIPT_PATH" /usr/local/bin/sn
            echo -e "${GREEN}✓ 快捷命令已创建：输入 'sn' 即可运行本脚本${PLAIN}"
        fi
        chmod +x /usr/local/bin/sn 2>/dev/null
    fi
}
create_shortcut

# 检测系统
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID=$ID
        if [[ "$ID" =~ (ubuntu|debian) ]]; then
            PKG_MANAGER="apt"
        elif [[ "$ID" =~ (centos|rhel|rocky|almalinux|fedora) ]]; then
            if [[ "$VERSION_ID" =~ ^7 ]]; then
                PKG_MANAGER="yum"
            else
                PKG_MANAGER="dnf"
            fi
        else
            PKG_MANAGER="unknown"
        fi
    elif [ -f /etc/redhat-release ]; then
        OS_ID="centos"
        grep -q "release 7" /etc/redhat-release && PKG_MANAGER="yum" || PKG_MANAGER="dnf"
    else
        PKG_MANAGER="unknown"
    fi
}
detect_os
echo -e "${GREEN}检测到系统: $OS_ID, 包管理器: $PKG_MANAGER${PLAIN}\n"

# 安装依赖（智能跳过）
echo -e "${YELLOW}正在检查并安装依赖包...${PLAIN}\n"
COMMON_PKGS="iperf3 mtr sysbench tar curl bc wget git vim net-tools dnsutils ethtool tcpdump nmap htop nmon lsof rsync pciutils usbutils ioping fio zip unzip bzip2 screen tmux jq tree cmake python3 python3-pip speedtest-cli nload iftop"

if [ "$PKG_MANAGER" = "apt" ]; then
    apt update -y
    for pkg in $COMMON_PKGS build-essential silversearcher-ag; do
        if dpkg -l | grep -q "^ii  $pkg "; then
            echo -e "${GREEN}[已安装] $pkg${PLAIN}"
        else
            echo -e "${BLUE}[安装] $pkg ...${PLAIN}"
            apt install -y $pkg
        fi
    done
elif [ "$PKG_MANAGER" = "yum" ]; then
    if ! rpm -q epel-release &>/dev/null; then
        yum install -y epel-release
    fi
    for pkg in $COMMON_PKGS epel-release gcc gcc-c++ make; do
        if rpm -q $pkg &>/dev/null; then
            echo -e "${GREEN}[已安装] $pkg${PLAIN}"
        else
            echo -e "${BLUE}[安装] $pkg ...${PLAIN}"
            yum install -y $pkg
        fi
    done
elif [ "$PKG_MANAGER" = "dnf" ]; then
    if ! rpm -q epel-release &>/dev/null; then
        dnf install -y epel-release
    fi
    for pkg in $COMMON_PKGS epel-release gcc gcc-c++ make; do
        if rpm -q $pkg &>/dev/null; then
            echo -e "${GREEN}[已安装] $pkg${PLAIN}"
        else
            echo -e "${BLUE}[安装] $pkg ...${PLAIN}"
            dnf install -y $pkg
        fi
    done
else
    echo -e "${RED}不支持的包管理器，跳过依赖安装${PLAIN}"
fi

# 安装 nexttrace
if ! command -v nexttrace &>/dev/null; then
    echo -e "${BLUE}安装 nexttrace ...${PLAIN}"
    wget -qO /usr/local/bin/nexttrace https://github.com/sjlleo/nexttrace/releases/latest/download/nexttrace_linux_amd64
    chmod +x /usr/local/bin/nexttrace
fi
export PATH=$PATH:/usr/local/bin
echo -e "${GREEN}依赖检查完成\n${PLAIN}"

# 设置主机名
CUR_HOST=$(hostname)
EXPECT_HOST="www.1373737.xyz"
if [ "$CUR_HOST" != "$EXPECT_HOST" ]; then
    echo -e "${BLUE}修改主机名: $CUR_HOST -> $EXPECT_HOST${PLAIN}"
    hostnamectl set-hostname "$EXPECT_HOST"
    echo "$EXPECT_HOST" > /etc/hostname
    sed -i "s/127.0.1.1.*/127.0.1.1 $EXPECT_HOST/g" /etc/hosts
    echo -e "${GREEN}主机名已修改${PLAIN}"
else
    echo -e "${GREEN}主机名已是 $EXPECT_HOST${PLAIN}"
fi
HOSTNAME=$(hostname)
echo ""

# 开启 BBR
echo -e "${YELLOW}配置 TCP BBR...${PLAIN}"
modprobe tcp_bbr 2>/dev/null || true
echo "tcp_bbr" >> /etc/modules-load.d/bbr.conf 2>/dev/null || true
grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf || echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf || echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
sysctl -p >/dev/null 2>&1
echo -e "${GREEN}BBR 已启用 (bbr3)${PLAIN}\n"

# 收集系统信息
echo -e "${YELLOW}收集系统信息...${PLAIN}\n"
OS_VERSION=$(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')
KERNEL_VER=$(uname -r)
ARCH=$(uname -m)
CPU_MODEL=$(lscpu | grep "Model name" | cut -d: -f2 | xargs)
[ -z "$CPU_MODEL" ] && CPU_MODEL=$(cat /proc/cpuinfo | grep "model name" | head -1 | cut -d: -f2 | xargs)
CPU_CORES=$(nproc)
CPU_FREQ=$(lscpu | grep "CPU MHz" | cut -d: -f2 | xargs | cut -d. -f1)
[ -z "$CPU_FREQ" ] && CPU_FREQ=$(cat /proc/cpuinfo | grep "cpu MHz" | head -1 | cut -d: -f2 | xargs | cut -d. -f1)
[ -z "$CPU_FREQ" ] && CPU_FREQ="未知"
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d% -f1)
LOAD_AVG=$(cat /proc/loadavg | awk '{print $1", "$2", "$3}')
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

# 网络流量
RX_BYTES=0; TX_BYTES=0
for dev in $(ls /sys/class/net/ | grep -v lo); do
    rx=$(cat /sys/class/net/$dev/statistics/rx_bytes 2>/dev/null)
    tx=$(cat /sys/class/net/$dev/statistics/tx_bytes 2>/dev/null)
    RX_BYTES=$((RX_BYTES + rx))
    TX_BYTES=$((TX_BYTES + tx))
done
RX_GB=$(echo "scale=2; $RX_BYTES/1073741824" | bc)
TX_GB=$(echo "scale=2; $TX_BYTES/1073741824" | bc)
[ -z "$RX_GB" ] && RX_GB=0
[ -z "$TX_GB" ] && TX_GB=0
RX_GB=$(printf "%.2f" $RX_GB)
TX_GB=$(printf "%.2f" $TX_GB)

TCP_ALGO=$(sysctl -n net.ipv4.tcp_congestion_control)
[ -z "$TCP_ALGO" ] && TCP_ALGO="bbr"
IPV4=$(curl -s4m5 ifconfig.co)
[ -z "$IPV4" ] && IPV4="未知"
IPV6=$(curl -s6m5 ifconfig.co)
[ -z "$IPV6" ] && IPV6="未配置"
ISP=$(curl -s4m5 ipinfo.io/org | cut -d' ' -f2-)
GEO_CITY=$(curl -s4m5 ipinfo.io/city)
GEO_COUNTRY=$(curl -s4m5 ipinfo.io/country)
GEO="${GEO_CITY}, ${GEO_COUNTRY}"
DNS1=$(grep -m1 nameserver /etc/resolv.conf | awk '{print $2}')
DNS2=$(grep -m2 nameserver /etc/resolv.conf | tail -n1 | awk '{print $2}')
[ -z "$DNS1" ] && DNS1="未知"
[ -z "$DNS2" ] && DNS2="无"
CURRENT_TIME=$(TZ='Asia/Shanghai' date "+%Y-%m-%d %H:%M %p")
UPTIME_SEC=$(cat /proc/uptime | awk '{print $1}')
DAYS=$(echo "$UPTIME_SEC/86400" | bc)
HOURS=$(echo "($UPTIME_SEC%86400)/3600" | bc)
MINUTES=$(echo "($UPTIME_SEC%3600)/60" | bc)
UPTIME_STR="${DAYS}天 ${HOURS}时 ${MINUTES}分"

# 虚拟化检测
VIRT_TYPE="物理机"
if command -v systemd-detect-virt &>/dev/null; then
    virt=$(systemd-detect-virt)
    case $virt in
        kvm) VIRT_TYPE="KVM虚拟化" ;;
        xen) VIRT_TYPE="Xen虚拟化" ;;
        vmware) VIRT_TYPE="VMware虚拟化" ;;
        microsoft) VIRT_TYPE="Hyper-V虚拟化" ;;
        openvz) VIRT_TYPE="OpenVZ虚拟化" ;;
        lxc) VIRT_TYPE="LXC容器" ;;
        docker) VIRT_TYPE="Docker容器" ;;
        *) VIRT_TYPE="其他虚拟化" ;;
    esac
fi

# 性能测试
echo -e "${BLUE}CPU 单核测试 (10秒)...${PLAIN}"
SINGLE_SCORE=$(sysbench cpu --cpu-max-prime=20000 --threads=1 --time=10 run 2>&1 | grep -E "events per second:" | awk '{print $4}')
[ -z "$SINGLE_SCORE" ] && SINGLE_SCORE=0
echo -e "${GREEN}单核得分: $SINGLE_SCORE${PLAIN}"

echo -e "${BLUE}CPU 多核测试 (10秒)...${PLAIN}"
MULTI_SCORE=$(sysbench cpu --cpu-max-prime=20000 --threads=$CPU_CORES --time=10 run 2>&1 | grep -E "events per second:" | awk '{print $4}')
[ -z "$MULTI_SCORE" ] && MULTI_SCORE=0
echo -e "${GREEN}多核得分: $MULTI_SCORE${PLAIN}"

echo -e "${BLUE}内存读测试...${PLAIN}"
MEM_READ=$(sysbench memory --memory-block-size=1M --memory-total-size=5G --memory-oper=read --time=10 run 2>&1 | grep "transferred" | awk '{print $4}' | head -1)
[ -z "$MEM_READ" ] && MEM_READ=0
echo -e "${GREEN}内存读: $MEM_READ MB/s${PLAIN}"

echo -e "${BLUE}内存写测试...${PLAIN}"
MEM_WRITE=$(sysbench memory --memory-block-size=1M --memory-total-size=5G --memory-oper=write --time=10 run 2>&1 | grep "transferred" | awk '{print $4}' | head -1)
[ -z "$MEM_WRITE" ] && MEM_WRITE=0
echo -e "${GREEN}内存写: $MEM_WRITE MB/s${PLAIN}"

# 硬盘 I/O 测试
echo -e "${BLUE}硬盘 I/O 测试...${PLAIN}"
rootdev=$(df / | tail -1 | cut -d' ' -f1)
devname=$(lsblk -no pkname $rootdev | head -1)
if [ -f /sys/block/$devname/queue/rotational ]; then
    if [ $(cat /sys/block/$devname/queue/rotational) -eq 0 ]; then
        DISK_TYPE="SSD"
    else
        DISK_TYPE="HDD"
    fi
else
    DISK_TYPE="未知"
fi

IO_SPEEDS=()
for i in 1 2 3; do
    echo -e "${BLUE}第 $i 次...${PLAIN}"
    dd if=/dev/urandom of=/tmp/test_io bs=1M count=128 oflag=direct 2>&1 | tee /tmp/dd_out
    speed=$(grep -oP '\d+(\.\d+)? MB/s' /tmp/dd_out | head -1 | sed 's/ MB\/s//')
    if [ -n "$speed" ]; then
        IO_SPEEDS+=($speed)
        echo -e "${GREEN}速度: $speed MB/s${PLAIN}"
    else
        IO_SPEEDS+=(0)
    fi
    rm -f /tmp/test_io /tmp/dd_out
    sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null
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

# 输出系统信息
echo ""
echo -e "${YELLOW}系统信息查询${PLAIN}"
echo "============================="
echo "主机名： $HOSTNAME"
echo "系统版本： $OS_VERSION"
echo "Linux版本： $KERNEL_VER"
echo "虚拟化类型： $VIRT_TYPE"
echo "============================="
echo "CPU架构： $ARCH"
echo "CPU型号： $CPU_MODEL"
echo "CPU核心数： $CPU_CORES"
echo "CPU频率： $CPU_FREQ MHz"
echo "CPU占用： $CPU_USAGE%"
echo "============================="
echo "系统负载： $LOAD_AVG"
echo "物理内存： $MEM_INFO"
echo "虚拟内存： $SWAP_INFO"
echo "硬盘占用： $DISK_INFO"
echo "============================="
echo "总接收： $RX_GB GB"
echo "总发送： $TX_GB GB"
echo "============================="
echo "网络算法： $TCP_ALGO"
echo "IPv4地址： $IPV4"
echo "IPv6地址： $IPV6"
echo "============================="
echo "运营商： $ISP"
echo "DNS地址： $DNS1 $DNS2"
echo "地理位置： $GEO"
echo "系统时间： $CURRENT_TIME"
echo ""
echo -e "${YELLOW}系统性能基准测试结果${PLAIN}"
echo "1线程测试（单核）得分： $SINGLE_SCORE Scores"
echo "${CPU_CORES}线程测试（多核）得分： $MULTI_SCORE Scores"
echo "============================="
echo "内存读测试： $MEM_READ MB/s"
echo "内存写测试： $MEM_WRITE MB/s"
echo "============================="
echo "系统运行时长： $UPTIME_STR"
echo ""
echo -e "${YELLOW}硬盘 I/O 性能测试${PLAIN}"
echo "硬盘性能测试结果如下："
echo -e "硬盘I/O（第一次测试）： ${YELLOW}${IO_SPEEDS[0]} MB/s${PLAIN}"
echo -e "硬盘I/O（第二次测试）： ${YELLOW}${IO_SPEEDS[1]} MB/s${PLAIN}"
echo -e "硬盘I/O（第三次测试）： ${YELLOW}${IO_SPEEDS[2]} MB/s${PLAIN}"
echo -e "硬盘I/O（平均测试）：  ${YELLOW}$AVG_SPEED MB/s${PLAIN}"
echo "硬盘类型： $DISK_TYPE"
echo "硬盘性能等级： $LEVEL"
echo -e "${GREEN}测试数据不是百分百准确，以官方宣称为主。${PLAIN}"
echo ""

# 外部测试（关键修复：使用正确 URL）
echo -e "${BLUE}========================================${PLAIN}"
echo -e "${BLUE}[1/8] 执行 IP 风险检查...${PLAIN}"
bash <(curl -Ls https://IP.Check.Place)
echo -e "${GREEN}完成${PLAIN}\n"

echo -e "${BLUE}========================================${PLAIN}"
echo -e "${BLUE}[2/8] 执行三网回程线路测试...${PLAIN}"
curl -sSf https://raw.githubusercontent.com/zhanghanyun/backtrace/main/install.sh | sh
curl -s https://raw.githubusercontent.com/anjing-liu/mtr_trace/main/mtr_trace.sh | bash
echo -e "${GREEN}完成${PLAIN}\n"

echo -e "${BLUE}========================================${PLAIN}"
echo -e "${BLUE}[3/8] 执行三网+教育网 IPv4 单线程测速...${PLAIN}"
echo "2" | bash <(curl -sL https://raw.githubusercontent.com/i-abc/Speedtest/main/speedtest.sh)
echo -e "${GREEN}完成${PLAIN}\n"

echo -e "${BLUE}========================================${PLAIN}"
echo -e "${BLUE}[4/8] 执行流媒体解锁测试...${PLAIN}"
printf "66\n" | bash <(curl -Ls https://check.unlock.media)
echo -e "${GREEN}完成${PLAIN}\n"

echo -e "${BLUE}========================================${PLAIN}"
echo -e "${BLUE}[5/8] 执行全国五网ISP路由回程测试...${PLAIN}"
{
    echo "1"
    sleep 1
    echo "8"
} | nexttrace --fast-trace
echo -e "${GREEN}完成${PLAIN}\n"

echo -e "${BLUE}========================================${PLAIN}"
echo -e "${BLUE}[6/8] 执行三网回程路由测试...${PLAIN}"
printf "y\n" | bash <(curl -Ls https://Net.Check.Place) -R
echo -e "${GREEN}完成${PLAIN}\n"

echo -e "${BLUE}========================================${PLAIN}"
echo -e "${BLUE}[7/8] 执行 bench 性能测试...${PLAIN}"
wget -qO- bench.sh | bash
echo -e "${GREEN}完成${PLAIN}\n"

echo -e "${BLUE}========================================${PLAIN}"
echo -e "${BLUE}[8/8] 执行超售测试...${PLAIN}"
wget --no-check-certificate -O memoryCheck.sh https://raw.githubusercontent.com/uselibrary/memoryCheck/main/memoryCheck.sh
chmod +x memoryCheck.sh
./memoryCheck.sh
rm -f memoryCheck.sh
echo -e "${GREEN}完成${PLAIN}\n"

# 总耗时
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
HOURS_ELAPSED=$((ELAPSED / 3600))
MINUTES_ELAPSED=$(((ELAPSED % 3600) / 60))
SECONDS_ELAPSED=$((ELAPSED % 60))
echo -e "${YELLOW}所有测试完成！总耗时: ${HOURS_ELAPSED}小时 ${MINUTES_ELAPSED}分钟 ${SECONDS_ELAPSED}秒${PLAIN}"
