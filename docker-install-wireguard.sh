#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 错误处理
die() {
    echo -e "${RED}[错误] $1${NC}" >&2
    read -p "按回车键退出..."
    exit 1
}

# 获取本机IP地址
get_local_ip() {
    ip -o -4 addr show | awk '{print $4}' | cut -d'/' -f1 | grep -v '127.0.0.1' | head -n1
}

# 精准系统检测
detect_system() {
    # 检测群辉DSM
    if [ -f /etc/synoinfo.conf ] && [ -d /var/packages ]; then
        echo "dsm"
        return
    fi

    # 检测FNOS系统
    if grep -q "ID=debian" /etc/os-release && ls /vol1* &>/dev/null; then
        echo "favbox"
        return
    fi

    # 检测其他Debian系统
    if grep -q "ID=debian" /etc/os-release; then
        echo "debian"
        return
    fi

    # 其他Linux系统
    if [ -f /etc/os-release ]; then
        echo "linux"
        return
    fi

    echo "unknown"
}

# 获取Docker目录
get_docker_dir() {
    local system_type=$1
    local dir=""

    case $system_type in
        "dsm") dir=$(find /volume* -maxdepth 1 -type d -name "docker" 2>/dev/null | head -n1)
               [ -z "$dir" ] && dir="/volume1/docker" ;;
        "favbox") dir=$(find /vol*/1000 -maxdepth 1 -type d -name "docker" 2>/dev/null | head -n1)
                  [ -z "$dir" ] && dir="/vol1/1000/docker" ;;
        *) dir="/opt/docker" ;;
    esac

    # 清理路径中的特殊字符
    dir=$(echo "$dir" | tr -d '\n\r')
    mkdir -p "$dir" || die "无法创建目录 $dir"
    echo "$dir"
}

# 生成随机WireGuard私钥
generate_wg_private_key() {
    # 生成符合WireGuard要求的私钥
    wg genkey | tr -d '\n\r'
}

# 获取管理员密码
get_admin_password() {
    while true; do
        read -p "请输入WireGuard管理员密码: " password
        
        # 检查长度
        if [ -z "$password" ]; then
            echo -e "${RED}错误: 密码不能为空${NC}"
            continue
        fi
        
        break
    done
    
    echo "$password"
}

# 安装WireGuard
install_wireguard() {
    local base_dir="$1"
    local data_dir="${base_dir}/wireguard"
    
    # 创建数据目录（确保路径没有特殊字符）
    data_dir=$(echo "$data_dir" | tr -d '\n\r')
    mkdir -p "$data_dir" || die "无法创建WireGuard数据目录: $data_dir"
    chmod 700 "$data_dir" || echo -e "${YELLOW}[警告] 无法设置目录权限${NC}"
    
    echo -e "${BLUE}[信息] 使用Docker目录: ${base_dir}${NC}"
    echo -e "${BLUE}[信息] WireGuard数据目录: ${data_dir}${NC}"

    # 获取管理员密码
    local admin_password=$(get_admin_password)
    
    # 生成WireGuard私钥
    local wg_private_key=$(generate_wg_private_key)
    echo -e "${BLUE}[信息] 生成的WireGuard私钥: ${YELLOW}${wg_private_key}${NC}"

    # 清理旧容器
    if docker ps -aq --filter "name=wg-server"; then
        echo -e "${YELLOW}[注意] 移除已存在的wg-server容器...${NC}"
        docker stop wg-server >/dev/null 2>&1
        docker rm wg-server >/dev/null 2>&1
    fi

    # 运行新容器
    echo -e "${BLUE}[信息] 正在启动WireGuard容器...${NC}"
    if ! docker run -it -d \
        --name=wg-server \
        --restart=always \
        --cap-add NET_ADMIN \
        --device /dev/net/tun:/dev/net/tun \
        -v "${data_dir}:/data" \
        -e "WG_ADMIN_PASSWORD=${admin_password}" \
        -e "WG_WIREGUARD_PRIVATE_KEY=${wg_private_key}" \
        -p 8000:8000/tcp \
        -p 51820:51820/udp \
        mfkd1000/docker_wg_server; then
        docker logs wg-server 2>&1 | head -n 20
        die "启动WireGuard容器失败，请检查上方日志"
    fi

    # 验证容器状态
    sleep 3
    if ! docker ps --filter "name=wg-server" --format "{{.Status}}" | grep -q "Up"; then
        docker logs wg-server 2>&1 | head -n 20
        die "容器启动后异常退出，请检查上方日志"
    fi

    local ip=$(get_local_ip)
    echo -e "\n${GREEN}========== 安装成功 ==========${NC}"
    echo -e "Web管理界面: ${GREEN}http://${ip}:8000${NC}"
    echo -e "管理员密码: ${YELLOW}${admin_password}${NC}"
    echo -e "WireGuard私钥: ${YELLOW}${wg_private_key}${NC}"
    echo -e "WireGuard端口: ${YELLOW}51820/udp${NC}"
    echo -e "数据目录: ${data_dir}"
    echo -e "查看日志: ${YELLOW}docker logs wg-server${NC}"
    echo -e "${YELLOW}请妥善保存管理员密码和WireGuard私钥！${NC}"
}

# 主流程
main() {
    echo -e "${BLUE}=== WireGuard VPN服务器自动化安装脚本 ===${NC}"
    
    # 检查Docker
    if ! command -v docker &>/dev/null; then
        die "Docker未安装，请先安装Docker"
    fi
    
    # 检查wg命令是否可用
    if ! command -v wg &>/dev/null; then
        echo -e "${YELLOW}[警告] WireGuard工具(wg)未安装，私钥生成可能不可靠${NC}"
    fi
    
    echo -e "${GREEN}[成功] Docker已安装: $(docker --version | cut -d ',' -f 1)${NC}"

    # 检测系统并获取目录
    system_type=$(detect_system)
    case $system_type in
        "dsm") echo -e "${GREEN}[系统] 检测到群辉DSM${NC}" ;;
        "favbox") echo -e "${GREEN}[系统] 检测到FNOS${NC}" ;;
        "debian") echo -e "${YELLOW}[系统] 检测到Debian${NC}" ;;
        "linux") echo -e "${YELLOW}[系统] 检测到通用Linux${NC}" ;;
        *) echo -e "${YELLOW}[警告] 系统类型未知，使用默认配置${NC}" ;;
    esac

    dir=$(get_docker_dir "$system_type")
    echo -e "${BLUE}[目录] 使用容器目录: ${dir}${NC}"

    # 安装WireGuard
    install_wireguard "$dir"

    read -p "按回车键退出..."
}

main "$@"