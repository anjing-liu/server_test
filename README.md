## 安装命令
```
wget -O server_test.sh https://raw.githubusercontent.com/anjing-liu/server_test/main/server_test.sh && chmod +x server_test.sh && sudo ./server_test.sh
```

## 服务器测试一键脚本- 功能说明

## 📄一、脚本概述

这是一个适用于 Linux 服务器的全自动测试脚本，支持 Ubuntu/Debian/CentOS/Rocky/AlmaLinux 等主流发行版。首次运行后会自动创建 sn 快捷命令，之后只需输入 sn 即可再次运行。


## 📦二、核心功能
系统环境准备

自动检测操作系统和包管理器（apt/yum/dnf）

智能安装所需依赖包（已安装的自动跳过）

自动安装 nexttrace 路由追踪工具

自动开启 TCP BBR 拥塞控制算法


### 系统信息收集

| 项目 | 说明 |
|------|------|
| 主机名 | 当前系统主机名 |
| 系统版本 | OS 发行版名称及版本 |
| Linux 内核版本 | 内核版本号 |
| 虚拟化类型 | KVM / Xen / VMware / Hyper-V / OpenVZ / LXC / Docker / 物理机 |
| CPU 架构 | x86_64 / aarch64 等 |
| CPU 型号 | 完整的 CPU 型号名称 |
| CPU 核心数 | 物理核心数（含超线程） |
| CPU 频率 | 当前运行频率（MHz 或 GHz） |
| CPU 占用率 | 当前使用百分比 |
| 系统负载 | 1 / 5 / 15 分钟平均负载 |
| 物理内存 | 总量 / 已用 / 使用率 |
| 虚拟内存 | 总量 / 已用 / 使用率 |
| 硬盘占用 | 根分区已用 / 总量 / 使用率 |
| 网络流量统计 | 总接收 / 总发送（智能显示 B / KB / MB / GB） |
| IPv4 地址 | 公网 IPv4 地址 |
| IPv6 地址 | 公网 IPv6 地址（没有IPv6 地址则显示"未配置"） |
| 运营商 | 网络服务提供商 |
| 地理位置 | 城市 / 国家 |
| DNS 地址 | 主 DNS / 备 DNS |
| 系统时间 | 北京时间（Asia/Shanghai） |

### 性能基准测试

| 测试项目 | 说明 | 时长 |
|----------|------|------|
| CPU 单核性能 | sysbench 素数计算测试（cpu-max-prime=20000） | 10 秒 |
| CPU 多核性能 | 使用全部核心进行测试（仅多核 CPU 显示） | 10 秒 |
| 内存读取速度 | 1M 块大小，5G 总量，读操作 | 10 秒 |
| 内存写入速度 | 1M 块大小，5G 总量，写操作 | 10 秒 |
| 硬盘 I/O 速度 | 三次 dd 测试取平均值（128M 文件，direct 模式） | 约 15 秒 |

**硬盘 I/O 性能等级划分**：


| 等级 | 速度范围 |
|:----:|----------|
| ⚠️ 一般 | < 100 MB/s |
| 📊 中等 | 100 - 200 MB/s |
| 👍 良好 | 200 - 500 MB/s |
| ⭐ 优秀 | > 500 MB/s |

###  网络质量测试（共9项）

| 序号 | 测试项目 | 说明 |
|:----:|----------|------|
| 1 | 系统信息收集 | 具体看系统信息收集部分 |
| 2 | IP 风险检查 | 检测 IP 是否被拉黑、是否为代理 |
| 3 | 三网回程线路测试 | 测试电信/联通/移动回程路由线路 |
| 4 | 三网+教育网 IPv4 单线程测速 | 测速到各运营商节点的下载速度 |
| 5 | 流媒体解锁测试 | 检测 Netflix/Disney+/YouTube 等解锁情况 |
| 6 | 全国五网 ISP 路由回程测试 | 五大运营商路由追踪 |
| 7 | 三网回程路由测试 | 详细路由追踪 |
| 8 | bench 性能测试 | 综合服务器性能测试（bench.sh） |
| 9 | 超售测试 | 检测服务器是否超售 |


## 三、快捷命令
首次运行脚本后，会自动创建快捷命令。任何时间，输入以下命令即可重新运行测试。
```
sn
```

## 📦四、安装依赖列表
脚本会自动安装以下工具（已存在的跳过）：

text
iperf3 mtr sysbench tar curl bc wget git vim net-tools dnsutils 
ethtool tcpdump nmap htop lsof rsync pciutils usbutils ioping fio 
zip unzip bzip2 screen tmux jq tree cmake python3 python3-pip 
speedtest-cli nload iftop build-essential (apt) / gcc gcc-c++ make (yum/dnf)
额外安装：nexttrace（路由追踪工具）


### 💻五、支持系统

| 系统 | 版本 | 支持状态 |
|------|------|:--------:|
| Ubuntu | 18.04+ | ✅ |
| Debian | 10+ | ✅ |
| CentOS | 7/8 | ✅ |
| Rocky Linux | 8/9 | ✅ |
| AlmaLinux | 8/9 | ✅ |
| Fedora | 35+ | ✅ |

### ⚠️六、注意事项
需要 root 权限运行（用于安装依赖和修改系统配置）

部分外部测试脚本可能需要联网下载，请确保网络通畅

测试耗时约 5-30 分钟，取决于服务器性能

硬盘测试会进行三次写入（每次128M），请注意 SSD 写入寿命

流媒体测试会自动选择，无需人工干预

### 🔧七、故障排查

| 问题 | 解决方法 |
|------|----------|
| `sn: command not found` | 重新运行脚本一次 |
| 依赖安装失败 | 检查网络连接，或手动安装对应包 |
| BBR 未生效 | 重启服务器后再次检查 |
| 外部测试卡住 | 可能是网络问题，按 `Ctrl+C` 跳过 |

### 🙏 致谢

感谢 [37VPS主机评测](https://www.1373737.xyz) 对本项目的支持。

本脚本集成了以下开源工具：

| 工具 | 用途 |
|------|------|
| [sysbench](https://github.com/akopytov/sysbench) | 性能测试 |
| [nexttrace](https://github.com/sjlleo/nexttrace) | 路由追踪 |
| [bench.sh](https://bench.sh) | 综合测试 |
| [IP.Check.Place](https://ip.check.place) | IP 风险检测 |
| [backtrace](https://github.com/zhanghanyun/backtrace) | 回程线路测试 |
