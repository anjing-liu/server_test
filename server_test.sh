#!/bin/bash
# ==================================================
# 服务器测试一键脚本
# 版本：4.5 - 最终修复版
# ==================================================

# 颜色定义
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
PLAIN='\033[0m'

# 设置环境变量 - 禁用所有交互式提示
export DEBIAN_FRONTEND=noninteractive
export DEBCONF_NONINTERACTIVE_SEEN=true
export UCF_FORCE_CONFFNEW=true
export UCF_FORCE_CONFFMISS=true

# 开始计时
START_TIME=$(date +%s)

# 检查是否为root用户
[[ $EUID -ne 0 ]] && echo -e "${RED}错误：请使用 root 用户运行此脚本${PLAIN}" && exit 1

set +e

# 全局标记文件
APT_UPDATED_FLAG="/tmp/apt_updated_$(date +%Y%m%d)"

# --------------------------------------------------
# 0. 检测系统类型
# --------------------------------------------------
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID=$ID
        OS_VERSION_ID=$VERSION_ID
        if [[ "$ID" == "ubuntu" ]] || [[ "$ID" == "debian" ]]; then
            PKG_MANAGER="apt"
        elif [[ "$ID" == "centos" ]] || [[ "$ID" == "rhel" ]] || [[ "$ID" == "rocky" ]] || [[ "$ID" == "almalinux" ]] || [[ "$ID" == "fedora" ]]; then
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
        if grep -q "release 7" /etc/redhat-release; then
            PKG_MANAGER="yum"
        else
            PKG_MANAGER="dnf"
        fi
    else
        PKG_MANAGER="unknown"
        OS_ID="unknown"
    fi
}

detect_os
echo -e "${GREEN}检测到系统: $OS_ID, 包管理器: $PKG_MANAGER${PLAIN}"
echo ""

# --------------------------------------------------
# 1. 安装依赖
# --------------------------------------------------
echo -e "${YELLOW}正在检查并安装依赖包...${PLAIN}"
echo ""

install_debian_deps() {
    echo -e "${BLUE}[包管理器] 检测到 Debian/Ubuntu 系统${PLAIN}"
    
    if [ ! -f "$APT_UPDATED_FLAG" ]; then
        echo -e "${BLUE}[包管理器] 正在更新软件源...${PLAIN}"
        apt update -y -qq 2>/dev/null
        touch "$APT_UPDATED_FLAG"
        echo -e "${GREEN}[包管理器] 软件源更新完成${PLAIN}"
    else
        echo -e "${GREEN}[包管理器] 软件源已是最新，跳过更新${PLAIN}"
    fi
    
    # 防止内核升级弹窗
    if [ -f /etc/needrestart/needrestart.conf ]; then
        sed -i 's/#$nrconf{restart} = '"'"'i'"'"';/$nrconf{restart} = '"'"'a'"'"';/g' /etc/needrestart/needrestart.conf 2>/dev/null
    fi
    
    local packages=(
        iperf3 mtr sysbench tar curl bc wget git vim net-tools dnsutils 
        ethtool tcpdump nmap htop nmon lsof rsync pciutils usbutils 
        ioping fio zip unzip bzip2 screen tmux jq tree 
        cmake python3 python3-pip speedtest-cli nload iftop
    )
    
    # 检查是否已安装 build-essential
    if ! dpkg -l 2>/dev/null | grep -q "^ii  build-essential "; then
        packages+=(build-essential)
    fi
    
    local missing_pkgs=()
    for pkg in "${packages[@]}"; do
        if dpkg -l 2>/dev/null | grep -q "^ii  $pkg "; then
            echo -e "${GREEN}[已安装] $pkg${PLAIN}"
        else
            missing_pkgs+=("$pkg")
        fi
    done
    
    if [ ${#missing_pkgs[@]} -gt 0 ]; then
        echo -e "${BLUE}[正在安装] ${#missing_pkgs[@]} 个依赖包...${PLAIN}"
        DEBIAN_FRONTEND=noninteractive apt install -y -qq "${missing_pkgs[@]}" 2>/dev/null
        echo -e "${GREEN}[完成] 依赖包安装完成${PLAIN}"
    else
        echo -e "${GREEN}[完成] 所有依赖包已安装${PLAIN}"
    fi
}

install_centos7_deps() {
    echo -e "${BLUE}[包管理器] 检测到 CentOS/RHEL 7 系统${PLAIN}"
    
    if ! rpm -q epel-release >/dev/null 2>&1; then
        echo -e "${BLUE}[包管理器] 正在启用 EPEL 源...${PLAIN}"
        rpm --import https://dl.fedoraproject.org/pub/epel/RPM-GPG-KEY-EPEL-7 2>/dev/null
        yum install -y epel-release 2>/dev/null
        echo -e "${GREEN}[包管理器] EPEL 源启用完成${PLAIN}"
    else
        echo -e "${GREEN}[包管理器] EPEL 源已启用${PLAIN}"
    fi
    
    local packages=(
        iperf3 mtr sysbench tar curl bc wget git vim net-tools bind-utils
        ethtool tcpdump nmap htop nmon lsof rsync pciutils usbutils
        ioping fio zip unzip bzip2 screen tmux jq tree
        gcc gcc-c++ make cmake python3 python3-pip speedtest-cli nload iftop
    )
    
    local missing_pkgs=()
    for pkg in "${packages[@]}"; do
        if rpm -q $pkg >/dev/null 2>&1; then
            echo -e "${GREEN}[已安装] $pkg${PLAIN}"
        else
            missing_pkgs+=("$pkg")
        fi
    done
    
    if [ ${#missing_pkgs[@]} -gt 0 ]; then
        echo -e "${BLUE}[正在安装] ${#missing_pkgs[@]} 个依赖包...${PLAIN}"
        yum install -y "${missing_pkgs[@]}" 2>/dev/null
        echo -e "${GREEN}[完成] 依赖包安装完成${PLAIN}"
    else
        echo -e "${GREEN}[完成] 所有依赖包已安装${PLAIN}"
    fi
}

install_centos8_deps() {
    echo -e "${BLUE}[包管理器] 检测到 CentOS/RHEL 8+ 系统${PLAIN}"
    
    if ! rpm -q epel-release >/dev/null 2>&1; then
        echo -e "${BLUE}[包管理器] 正在启用 EPEL 源...${PLAIN}"
        rpm --import https://dl.fedoraproject.org/pub/epel/RPM-GPG-KEY-EPEL-8 2>/dev/null
        dnf install -y epel-release 2>/dev/null
        echo -e "${GREEN}[包管理器] EPEL 源启用完成${PLAIN}"
    else
        echo -e "${GREEN}[包管理器] EPEL 源已启用${PLAIN}"
    fi
    
    local packages=(
        iperf3 mtr sysbench tar curl bc wget git vim net-tools bind-utils
        ethtool tcpdump nmap htop nmon lsof rsync pciutils usbutils
        ioping fio zip unzip bzip2 screen tmux jq tree
        gcc gcc-c++ make cmake python3 python3-pip speedtest-cli nload iftop
    )
    
    local missing_pkgs=()
    for pkg in "${packages[@]}"; do
        if rpm -q $pkg >/dev/null 2>&1; then
            echo -e "${GREEN}[已安装] $pkg${PLAIN}"
        else
            missing_pkgs+=("$pkg")
        fi
    done
    
    if [ ${#missing_pkgs[@]} -gt 0 ]; then
        echo -e "${BLUE}[正在安装] ${#missing_pkgs[@]} 个依赖包...${PLAIN}"
        dnf install -y "${missing_pkgs[@]}" 2>/dev/null
        echo -e "${GREEN}[完成] 依赖包安装完成${PLAIN}"
    else
        echo -e "${GREEN}[完成] 所有依赖包已安装${PLAIN}"
    fi
}

case $PKG_MANAGER in
    apt)
        install_debian_deps
        ;;
    yum)
        install_centos7_deps
        ;;
    dnf)
        install_centos8_deps
        ;;
    *)
        echo -e "${RED}不支持的包管理器，跳过依赖安装${PLAIN}"
        ;;
esac

# 安装 nexttrace
if ! command -v nexttrace &>/dev/null; then
    echo -e "${BLUE}[正在安装] nexttrace ...${PLAIN}"
    wget -qO- https://raw.githubusercontent.com/sjlleo/nexttrace/main/install.sh 2>/dev/null | bash
    echo -e "${GREEN}[完成] nexttrace${PLAIN}"
fi

echo -e "${GREEN}依赖包检查完成${PLAIN}"
echo ""

# --------------------------------------------------
# 2. 设置主机名
# --------------------------------------------------
CURRENT_HOSTNAME=$(hostname)
EXPECTED_HOSTNAME="www.1373737.xyz"

if [[ "$CURRENT_HOSTNAME" != "$EXPECTED_HOSTNAME" ]]; then
    echo -e "${BLUE}检测到主机名为: $CURRENT_HOSTNAME${PLAIN}"
    echo -e "${BLUE}正在修改主机名为: $EXPECTED_HOSTNAME${PLAIN}"
    hostnamectl set-hostname "$EXPECTED_HOSTNAME" 2>/dev/null
    echo "$EXPECTED_HOSTNAME" > /etc/hostname 2>/dev/null
    sed -i "s/127.0.1.1.*/127.0.1.1 $EXPECTED_HOSTNAME/g" /etc/hosts 2>/dev/null
    echo -e "${GREEN}主机名修改完成${PLAIN}"
else
    echo -e "${GREEN}主机名已经是 $EXPECTED_HOSTNAME${PLAIN}"
fi

HOSTNAME=$(hostname | cut -d'.' -f1)
echo ""

# --------------------------------------------------
# 3. BBR v3 安装和配置
# --------------------------------------------------
echo -e "${YELLOW}正在配置 TCP BBR...${PLAIN}"

kernel_version=$(uname -r)
major_version=$(echo "$kernel_version" | awk -F. '{print $1}')
minor_version=$(echo "$kernel_version" | awk -F. '{print $2}' | cut -d- -f1)

if [[ "$OS_ID" == "centos" && "$PKG_MANAGER" == "yum" ]]; then
    echo -e "${YELLOW}CentOS 7 内核版本 $kernel_version，使用原始 BBR${PLAIN}"
    modprobe tcp_bbr 2>/dev/null
    echo "tcp_bbr" >> /etc/modules-load.d/modules.conf 2>/dev/null
    grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf || echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf || echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p >/dev/null 2>&1
    echo -e "${GREEN}原始 BBR 安装完成${PLAIN}"
elif [[ $major_version -lt 5 || ($major_version -eq 5 && $minor_version -lt 6) ]]; then
    echo -e "${RED}当前内核版本 $kernel_version 不支持 BBR v3${PLAIN}"
    echo -e "${YELLOW}正在安装原始 BBR...${PLAIN}"
    modprobe tcp_bbr 2>/dev/null
    echo "tcp_bbr" >> /etc/modules-load.d/modules.conf 2>/dev/null
    grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf || echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf || echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p >/dev/null 2>&1
    echo -e "${GREEN}原始 BBR 安装完成${PLAIN}"
else
    echo -e "${GREEN}内核版本 $kernel_version 支持 BBR v3${PLAIN}"
    modprobe tcp_bbr 2>/dev/null
    echo "tcp_bbr" >> /etc/modules-load.d/modules.conf 2>/dev/null
    grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf || echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf || echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p >/dev/null 2>&1
    echo -e "${GREEN}BBR v3 安装完成${PLAIN}"
fi

echo -e "${BLUE}正在检查 BBR 状态...${PLAIN}"
if lsmod | grep -q tcp_bbr; then
    echo -e "${GREEN}BBR 模块已加载${PLAIN}"
else
    echo -e "${RED}BBR 模块未加载${PLAIN}"
fi

current_congestion=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
echo -e "${GREEN}当前拥塞控制算法: $current_congestion${PLAIN}"
echo ""

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

# CPU 型号
if command -v lscpu &>/dev/null; then
    CPU_MODEL=$(lscpu | grep "Model name" | awk -F':' '{print $2}' | xargs)
    [ -z "$CPU_MODEL" ] && CPU_MODEL=$(lscpu | grep "型号名称" | awk -F':' '{print $2}' | xargs)
else
    CPU_MODEL=$(cat /proc/cpuinfo | grep "model name" | head -1 | awk -F':' '{print $2}' | xargs)
fi
[ -z "$CPU_MODEL" ] && CPU_MODEL="未知"

CPU_CORES=$(nproc)
[ -z "$CPU_CORES" ] && CPU_CORES=1

# CPU 频率（多级降级获取）
CPU_FREQ=""
if command -v lscpu &>/dev/null; then
    CPU_FREQ=$(lscpu 2>/dev/null | grep "CPU MHz" | awk -F':' '{print $2}' | xargs | cut -d'.' -f1)
    [ -z "$CPU_FREQ" ] && CPU_FREQ=$(lscpu 2>/dev/null | grep "CPU动态频率" | awk -F':' '{print $2}' | xargs | cut -d'.' -f1)
    [ -z "$CPU_FREQ" ] && CPU_FREQ=$(lscpu 2>/dev/null | grep "CPU max MHz" | awk -F':' '{print $2}' | xargs | cut -d'.' -f1)
fi
if [ -z "$CPU_FREQ" ]; then
    CPU_FREQ=$(cat /proc/cpuinfo 2>/dev/null | grep "cpu MHz" | head -1 | awk -F':' '{print $2}' | xargs | cut -d'.' -f1)
fi
if [ -z "$CPU_FREQ" ] && [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq ]; then
    CPU_FREQ=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null)
    [ -n "$CPU_FREQ" ] && CPU_FREQ=$((CPU_FREQ / 1000))
fi
[ -z "$CPU_FREQ" ] && CPU_FREQ="未知"

CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
if [ -z "$CPU_USAGE" ]; then
    CPU_USAGE=$(top -bn1 | grep "%Cpu" | awk '{print $2}')
fi
[ -z "$CPU_USAGE" ] && CPU_USAGE=0

LOAD_AVG=$(cat /proc/loadavg 2>/dev/null | awk '{print $1", "$2", "$3}')
[ -z "$LOAD_AVG" ] && LOAD_AVG="0, 0, 0"

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

# IPv6 地址（静默获取，不显示错误）
IPV6=$(curl -s6m5 ifconfig.co 2>/dev/null || curl -s6m5 icanhazip.com 2>/dev/null)
if [ -z "$IPV6" ]; then
    IPV6="未配置"
fi

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
# 5. 虚拟化检测
# --------------------------------------------------
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
elif [ -f /proc/cpuinfo ]; then
    if grep -q "hypervisor" /proc/cpuinfo; then
        VIRT_TYPE="虚拟化（未知类型）"
    fi
fi

# --------------------------------------------------
# 6. 性能基准测试
# --------------------------------------------------
echo -e "${BLUE}正在进行 CPU 性能测试（单核）...${PLAIN}"
echo -e "${YELLOW}→ 正在密集计算素数，CPU 将满载 10 秒...${PLAIN}"
SINGLE_SCORE=$(sysbench cpu --cpu-max-prime=20000 --threads=1 --time=10 run 2>&1 | grep -E "events per second:|总事件数:" | awk '{print $NF}')
if [ -n "$SINGLE_SCORE" ] && [ "$SINGLE_SCORE" != "0" ]; then
    echo -e "${GREEN}✓ 单核测试完成，得分: ${SINGLE_SCORE}${PLAIN}"
else
    SINGLE_SCORE=0
    echo -e "${RED}✗ 单核测试失败${PLAIN}"
fi
echo ""

echo -e "${BLUE}正在进行 CPU 性能测试（多核，${CPU_CORES} 核心）...${PLAIN}"
echo -e "${YELLOW}→ 所有核心同时密集计算，将持续 10 秒...${PLAIN}"
MULTI_SCORE=$(sysbench cpu --cpu-max-prime=20000 --threads=$CPU_CORES --time=10 run 2>&1 | grep -E "events per second:|总事件数:" | awk '{print $NF}')
if [ -n "$MULTI_SCORE" ] && [ "$MULTI_SCORE" != "0" ]; then
    echo -e "${GREEN}✓ 多核测试完成，得分: ${MULTI_SCORE}${PLAIN}"
else
    MULTI_SCORE=0
    echo -e "${RED}✗ 多核测试失败${PLAIN}"
fi
echo ""

echo -e "${BLUE}正在进行内存读测试...${PLAIN}"
echo -e "${YELLOW}→ 正在读取 5GB 内存数据...${PLAIN}"
MEM_READ=$(sysbench memory --memory-block-size=1M --memory-total-size=5G --memory-oper=read --time=10 run 2>&1 | grep "transferred" | awk '{print $4}' | head -1 | sed 's/(//g')
if [ -n "$MEM_READ" ] && [ "$MEM_READ" != "0" ]; then
    echo -e "${GREEN}✓ 内存读测试完成，速度: ${MEM_READ} MB/s${PLAIN}"
else
    MEM_READ="0"
    echo -e "${RED}✗ 内存读测试失败${PLAIN}"
fi
echo ""

echo -e "${BLUE}正在进行内存写测试...${PLAIN}"
echo -e "${YELLOW}→ 正在写入 5GB 内存数据...${PLAIN}"
MEM_WRITE=$(sysbench memory --memory-block-size=1M --memory-total-size=5G --memory-oper=write --time=10 run 2>&1 | grep "transferred" | awk '{print $4}' | head -1 | sed 's/(//g')
if [ -n "$MEM_WRITE" ] && [ "$MEM_WRITE" != "0" ]; then
    echo -e "${GREEN}✓ 内存写测试完成，速度: ${MEM_WRITE} MB/s${PLAIN}"
else
    MEM_WRITE="0"
    echo -e "${RED}✗ 内存写测试失败${PLAIN}"
fi
echo ""

# --------------------------------------------------
# 7. 硬盘 I/O 性能测试（使用随机数据避免缓存）
# --------------------------------------------------
echo -e "${BLUE}正在进行硬盘 I/O 性能测试...${PLAIN}"
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
    echo -e "${BLUE}硬盘测试第 $i/3 次...${PLAIN}"
    # 使用 /dev/urandom 生成随机数据，避免缓存影响
    dd if=/dev/urandom of=/tmp/test_io bs=1M count=256 oflag=direct 2>&1 | tee /tmp/dd_output
    SPEED=$(grep -oP '\d+(\.\d+)? MB/s' /tmp/dd_output | head -1 | sed 's/ MB\/s//')
    if [ -n "$SPEED" ]; then
        IO_SPEEDS+=($SPEED)
        echo -e "${GREEN}第 $i 次测试速度: ${SPEED} MB/s${PLAIN}"
    else
        IO_SPEEDS+=(0)
        echo -e "${YELLOW}第 $i 次测试失败${PLAIN}"
    fi
    rm -f /tmp/test_io /tmp/dd_output 2>/dev/null
    sync
    echo 3 > /proc/sys/vm/drop_caches 2>/dev/null
    sleep 2
done

AVG_SPEED=$(echo "scale=2; (${IO_SPEEDS[0]}+${IO_SPEEDS[1]}+${IO_SPEEDS[2]})/3" | bc 2>/dev/null)
[ -z "$AVG_SPEED" ] && AVG_SPEED=0

if (( $(echo "$AVG_SPEED < 100" | bc -l 2>/dev/null) )); then
    LEVEL="一般"
elif (( $(echo "$AVG_SPEED < 200" | bc -l 2>/dev/null) )); then
    LEVEL="中等"
elif (( $(echo "$AVG_SPEED < 500" | bc -l 2>/dev/null) )); then
    LEVEL="良好"
else
    LEVEL="优秀"
fi

# --------------------------------------------------
# 8. 输出系统信息
# --------------------------------------------------
echo ""
echo -e "${YELLOW}系统信息查询${PLAIN}"
echo "============================="
echo "主机名： ${HOSTNAME}"
echo "系统版本： ${OS_VERSION}"
echo "Linux版本： ${KERNEL_VER}"
echo "虚拟化类型： ${VIRT_TYPE}"
echo "============================="
echo "CPU架构： ${ARCH}"
echo "CPU型号： ${CPU_MODEL}"
echo "CPU核心数： ${CPU_CORES}"
echo "CPU频率： ${CPU_FREQ} GHz"
echo "CPU占用： ${CPU_USAGE}%"
echo "============================="
echo "系统负载： ${LOAD_AVG}"
echo "物理内存： ${MEM_INFO}"
echo "虚拟内存： ${SWAP_INFO}"
echo "硬盘占用： ${DISK_INFO}"
echo "============================="
echo "总接收： ${RX_GB} GB"
echo "总发送： ${TX_GB} GB"
echo "============================="
echo "网络算法： ${TCP_ALGO}"
echo "IPv4地址： ${IPV4}"
echo "IPv6地址： ${IPV6}"
echo "============================="
echo "运营商： ${ISP}"
echo "DNS地址： ${DNS1} ${DNS2}"
echo "地理位置： ${GEO}"
echo "系统时间： ${CURRENT_TIME}"
echo ""
echo -e "${YELLOW}系统性能基准测试结果${PLAIN}"
echo "1线程测试（单核）得分： ${SINGLE_SCORE} Scores"
echo "${CPU_CORES}线程测试（多核）得分： ${MULTI_SCORE} Scores"
echo "============================="
echo "内存读测试： ${MEM_READ} MB/s"
echo "内存写测试： ${MEM_WRITE} MB/s"
echo "============================="
echo "系统运行时长： ${UPTIME_STR}"
echo ""
echo -e "${YELLOW}硬盘 I/O 性能测试${PLAIN}"
echo "硬盘性能测试结果如下："
echo -e "硬盘I/O（第一次测试）： ${YELLOW}${IO_SPEEDS[0]} MB/s${PLAIN}"
echo -e "硬盘I/O（第二次测试）： ${YELLOW}${IO_SPEEDS[1]} MB/s${PLAIN}"
echo -e "硬盘I/O（第三次测试）： ${YELLOW}${IO_SPEEDS[2]} MB/s${PLAIN}"
echo -e "硬盘I/O（平均测试）：  ${YELLOW}${AVG_SPEED} MB/s${PLAIN}"
echo "硬盘类型： ${DISK_TYPE}"
echo "硬盘性能等级： ${LEVEL}"
echo -e "${GREEN}测试数据不是百分百准确，以官方宣称为主。${PLAIN}"
echo ""

# --------------------------------------------------
# 9. 执行外部测试脚本（确保有输出）
# --------------------------------------------------
echo -e "${BLUE}执行 IP 风险检查...${PLAIN}"
curl -s --connect-timeout 15 https://ipcheck.place 2>/dev/null | bash
if [ $? -ne 0 ]; then
    echo -e "${YELLOW}IP 风险检查暂时不可用，跳过${PLAIN}"
fi
echo ""

echo -e "${BLUE}执行三网回程线路测试...${PLAIN}"
curl -s --connect-timeout 15 https://raw.githubusercontent.com/zhanghanyun/backtrace/main/install.sh 2>/dev/null | sh
if [ $? -ne 0 ]; then
    echo -e "${YELLOW}回程测试暂时不可用，跳过${PLAIN}"
fi
curl -s --connect-timeout 15 https://raw.githubusercontent.com/anjing-liu/mtr_trace/main/mtr_trace.sh 2>/dev/null | bash
echo ""

echo -e "${BLUE}执行三网+教育网 IPv4 单线程测速...${PLAIN}"
echo "2" | bash <(curl -sL --connect-timeout 15 https://raw.githubusercontent.com/i-abc/Speedtest/main/speedtest.sh) 2>/dev/null
echo ""

echo -e "${BLUE}执行流媒体解锁测试...${PLAIN}"
echo "" | bash <(curl -L -s --connect-timeout 15 https://check.unlock.media) 2>/dev/null
echo ""

echo -e "${BLUE}执行全国五网ISP路由回程测试...${PLAIN}"
printf "1\n8\n" | nexttrace --fast-trace 2>/dev/null
echo ""

echo -e "${BLUE}执行三网回程路由测试...${PLAIN}"
bash <(curl -Ls --connect-timeout 15 https://netcheck.place) -R 2>/dev/null
echo ""

echo -e "${BLUE}执行 bench 性能测试...${PLAIN}"
wget -qO- --timeout=30 bench.sh 2>/dev/null | bash
echo ""

echo -e "${BLUE}执行超售测试...${PLAIN}"
wget --timeout=30 --no-check-certificate -O memoryCheck.sh https://raw.githubusercontent.com/uselibrary/memoryCheck/main/memoryCheck.sh 2>/dev/null && chmod +x memoryCheck.sh && bash memoryCheck.sh 2>/dev/null
rm -f memoryCheck.sh 2>/dev/null
echo ""

# --------------------------------------------------
# 10. 总耗时统计
# --------------------------------------------------
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
HOURS_ELAPSED=$((ELAPSED / 3600))
MINUTES_ELAPSED=$(((ELAPSED % 3600) / 60))
SECONDS_ELAPSED=$((ELAPSED % 60))

echo -e "${YELLOW}所有测试完成！总耗时: ${HOURS_ELAPSED}小时 ${MINUTES_ELAPSED}分钟 ${SECONDS_ELAPSED}秒${PLAIN}"
