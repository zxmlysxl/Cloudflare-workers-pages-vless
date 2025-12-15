#!/bin/bash

# ================================================================
# Cloudflare Socks5/Http 本地代理脚本
# 作者: 甬哥
# Github: github.com/yonggekkk
# ================================================================

set -e
export LANG=en_US.UTF-8

# ============ 全局变量 ============
readonly SCRIPT_DIR="$HOME/cfs5http"
readonly BINARY_PATH="$SCRIPT_DIR/cfwp"
readonly GITHUB_RAW_URL="https://raw.githubusercontent.com/yonggekkk/Cloudflare-vless-trojan/main/s5http_wkpgs"
readonly INIT_SYSTEM=$(cat /proc/1/comm 2>/dev/null || echo "unknown")

# ============ 颜色定义 ============
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# ============ 工具函数 ============

# 打印信息
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# 打印成功信息
print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# 打印警告信息
print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# 打印错误信息并退出
print_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

# 检测 CPU 架构
detect_cpu_arch() {
    local arch=$(uname -m)
    case "$arch" in
        x86_64|x64|amd64)           echo "amd64" ;;
        i386|i686)                  echo "386" ;;
        armv8|armv8l|arm64|aarch64) echo "arm64" ;;
        armv7l)                     echo "arm" ;;
        mips64le)                   echo "mips64le" ;;
        mips64)                     echo "mips64" ;;
        mips|mipsle)                echo "mipsle" ;;
        *)
            print_error "当前架构 $arch 暂不支持"
            ;;
    esac
}

# 显示已安装节点
show_installed_nodes() {
    local ports=$(ps aux 2>/dev/null | grep "$BINARY_PATH" | grep -v grep | sed -n 's/.*client_ip=:\([0-9]\+\).*/\1/p')
    
    if [ -n "$ports" ]; then
        echo -e "${GREEN}已安装节点端口：${NC}"
        echo "$ports" | while IFS= read -r port; do
            echo "  - $port"
        done
    else
        echo -e "${YELLOW}未安装任何节点${NC}"
    fi
}

# 删除 systemd 服务
remove_systemd_service() {
    local port=$1
    local service_name="cf_${port}.service"
    
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        systemctl stop "$service_name" >/dev/null 2>&1
        systemctl disable "$service_name" >/dev/null 2>&1
        rm -f "/etc/systemd/system/$service_name"
        systemctl daemon-reload >/dev/null 2>&1
        print_info "已移除 systemd 服务: $service_name"
    fi
}

# 验证端口号
validate_port() {
    local port=$1
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        print_error "无效的端口号: $port (有效范围: 1-65535)"
    fi
}

# 验证域名格式
validate_domain() {
    local domain=$1
    if [ -z "$domain" ]; then
        print_error "域名不能为空"
    fi
    
    if ! [[ "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*:[0-9]+$ ]]; then
        print_warning "域名格式可能不正确，标准格式: domain.com:443"
    fi
}

# 下载二进制文件
download_binary() {
    local cpu_arch=$(detect_cpu_arch)
    local url="${GITHUB_RAW_URL}/linux-${cpu_arch}"
    
    print_info "正在下载程序文件..."
    
    if ! curl -L -o "$BINARY_PATH" -# --retry 3 --connect-timeout 10 --insecure "$url"; then
        print_error "下载失败，请检查网络连接"
    fi
    
    chmod +x "$BINARY_PATH"
    print_success "程序下载完成"
}

# 获取用户输入
get_input() {
    local prompt=$1
    local default=$2
    local var_name=$3
    
    read -p "$prompt" input
    eval "$var_name=\"${input:-$default}\""
}

# ============ 主要功能函数 ============

# 安装新节点
install_node() {
    mkdir -p "$SCRIPT_DIR"
    
    # 下载二进制文件（如果不存在）
    if [ ! -s "$BINARY_PATH" ]; then
        download_binary
    fi
    
    echo
    print_info "开始配置新节点..."
    echo
    
    # 1. 端口设置
    local port
    get_input "1、客户端本地端口 (默认: 30000): " "30000" port
    validate_port "$port"
    
    # 检查端口是否已被占用
    if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
        print_error "端口 $port 已被占用，请选择其他端口"
    fi
    
    # 2. CF 域名设置
    local cf_domain
    get_input "2、CF workers/pages/自定义域名 (格式: domain.com:443): " "" cf_domain
    validate_domain "$cf_domain"
    
    # 3. 优选 IP
    local cf_cdnip
    get_input "3、客户端地址优选IP/域名 (默认: yg1.ygkkk.dpdns.org): " "yg1.ygkkk.dpdns.org" cf_cdnip
    
    # 4. 密钥设置
    local token
    get_input "4、密钥设置 (留空表示不设密钥): " "" token
    
    # 5. DoH 服务器
    local dns
    get_input "5、DoH 服务器 (默认: dns.alidns.com/dns-query): " "dns.alidns.com/dns-query" dns
    
    # 6. ECH 开关
    local enable_ech
    read -p "6、ECH开关 (y=开启, n=关闭, 默认: 开启): " ech_input
    enable_ech=$([ -z "$ech_input" ] || [ "$ech_input" = "y" ] && echo "y" || echo "n")
    
    # 7. 分流开关
    local cnrule
    read -p "7、分流开关 (y=国内外分流, n=全局代理, 默认: 分流): " cnrule_input
    cnrule=$([ -z "$cnrule_input" ] || [ "$cnrule_input" = "y" ] && echo "y" || echo "n")
    
    echo
    print_info "正在创建配置文件..."
    
    # 创建启动脚本
    local script_path="$SCRIPT_DIR/cf_${port}.sh"
    cat > "$script_path" << EOF
#!/bin/bash
INIT_SYSTEM=\$(cat /proc/1/comm 2>/dev/null || echo "unknown")
CMD="$BINARY_PATH \\
client_ip=:$port \\
dns=$dns \\
cf_domain=$cf_domain \\
cf_cdnip=$cf_cdnip \\
token=$token \\
enable_ech=$enable_ech \\
cnrule=$cnrule"
LOG="$SCRIPT_DIR/${port}.log"

if [ "\$INIT_SYSTEM" = "systemd" ]; then
    exec \$CMD
else
    nohup \$CMD > "\$LOG" 2>&1 &
fi
EOF
    
    chmod +x "$script_path"
    
    # 根据 init 系统启动服务
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        # 创建 systemd 服务
        cat > "/etc/systemd/system/cf_${port}.service" << EOF
[Unit]
Description=CF Proxy Service on Port $port
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash $script_path
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload >/dev/null 2>&1
        systemctl start "cf_${port}.service" >/dev/null 2>&1
        systemctl enable "cf_${port}.service" >/dev/null 2>&1
        print_success "Systemd 服务已启动并设置为开机自启"
        
    elif [ "$INIT_SYSTEM" = "procd" ]; then
        # OpenWrt 等系统
        local rclocal="/etc/rc.local"
        [ ! -f "$rclocal" ] && echo -e "#!/bin/sh\nexit 0" > "$rclocal"
        
        if ! grep -q "$script_path" "$rclocal"; then
            if grep -q "^exit 0" "$rclocal"; then
                sed -i "/^exit 0/i /bin/bash $script_path" "$rclocal"
            else
                echo "/bin/bash $script_path" >> "$rclocal"
            fi
            
            if ! tail -n1 "$rclocal" | grep -q "^exit 0"; then
                echo "exit 0" >> "$rclocal"
            fi
        fi
        bash "$script_path"
        print_success "服务已启动并添加到开机自启"
    else
        bash "$script_path"
        print_success "服务已启动（非 systemd 环境，请手动设置开机自启）"
    fi
    
    echo
    print_success "安装完成！等待服务启动..."
    sleep 3
    
    # 显示配置信息
    local log_file="$SCRIPT_DIR/${port}.log"
    local timeout=10
    while [ $timeout -gt 0 ]; do
        if [ -f "$log_file" ] && grep -q '服务端域名与端口\|客户端地址与端口\|运行中的优选IP' "$log_file" 2>/dev/null; then
            echo
            echo "========================================"
            print_success "节点配置信息"
            echo "========================================"
            head -n 16 "$log_file" | grep '服务端域名与端口\|客户端地址与端口\|运行中的优选IP'
            echo "========================================"
            echo
            break
        fi
        sleep 1
        ((timeout--))
    done
    
    if [ $timeout -eq 0 ]; then
        print_warning "服务启动可能需要更长时间，请稍后使用菜单选项 2 查看日志"
    fi
}

# 查看节点信息
view_node_info() {
    show_installed_nodes
    echo
    
    local port
    read -p "请输入要查看的端口号: " port
    validate_port "$port"
    
    local log_file="$SCRIPT_DIR/${port}.log"
    
    if [ ! -f "$log_file" ]; then
        print_error "未找到端口 $port 的日志文件"
    fi
    
    echo
    echo "========================================"
    echo -e "${GREEN}端口 $port 节点配置信息${NC}"
    echo "========================================"
    sed -n '1,16p' "$log_file" 2>/dev/null | grep '服务端域名与端口\|客户端地址与端口\|运行中的优选IP' || echo "暂无配置信息"
    echo "========================================"
    echo -e "${GREEN}最近日志 (最后 10 行):${NC}"
    echo "========================================"
    sed '1,16d' "$log_file" 2>/dev/null | tail -n 10 || echo "暂无日志"
    echo "========================================"
    echo
}

# 删除单个节点
delete_node() {
    show_installed_nodes
    echo
    
    local port
    read -p "请输入要删除的端口号: " port
    validate_port "$port"
    
    print_info "正在删除端口 $port 的节点..."
    
    # 删除 systemd 服务
    remove_systemd_service "$port"
    
    # 终止进程
    local pid=$(lsof -t -i :$port 2>/dev/null)
    if [ -n "$pid" ]; then
        kill -9 $pid >/dev/null 2>&1
        print_success "已终止端口 $port 的进程 (PID: $pid)"
    else
        print_warning "端口 $port 没有运行中的进程"
    fi
    
    # 删除文件
    rm -f "$SCRIPT_DIR/${port}.log" "$SCRIPT_DIR/cf_${port}.sh"
    print_success "已删除端口 $port 的配置文件"
    
    echo
    print_success "节点删除完成"
}

# 卸载所有节点
uninstall_all() {
    local ports=$(ps aux 2>/dev/null | grep "$BINARY_PATH" | grep -v grep | sed -n 's/.*client_ip=:\([0-9]\+\).*/\1/p')
    
    if [ -z "$ports" ]; then
        print_warning "没有找到已安装的节点"
        read -p "是否删除程序目录？(y/n): " confirm
        if [ "$confirm" = "y" ]; then
            rm -rf "$SCRIPT_DIR" "$0"
            print_success "卸载完成"
        fi
        return
    fi
    
    echo
    print_warning "即将删除所有节点，此操作不可恢复！"
    show_installed_nodes
    echo
    read -p "确认卸载所有节点？(y/n): " confirm
    
    if [ "$confirm" != "y" ]; then
        print_info "已取消操作"
        return
    fi
    
    print_info "正在卸载所有节点..."
    
    # 删除所有 systemd 服务
    echo "$ports" | while IFS= read -r port; do
        remove_systemd_service "$port"
    done
    
    # 终止所有进程
    ps aux 2>/dev/null | grep "$BINARY_PATH" | grep -v grep | awk '{print $2}' | xargs -r kill -9 2>/dev/null
    
    # 删除目录和脚本
    rm -rf "$SCRIPT_DIR" "$0"
    
    print_success "所有节点已卸载完成"
}

# 显示主菜单
show_menu() {
    clear
    echo "================================================================"
    echo -e "${BLUE}甬哥 Cloudflare Socks5/Http 本地代理脚本${NC}"
    echo "================================================================"
    echo "Github  : github.com/yonggekkk"
    echo "Blogger : ygkkk.blogspot.com"
    echo "YouTube : www.youtube.com/@ygkkk"
    echo "================================================================"
    echo "支持: Workers域名、Pages域名、自定义域名"
    echo "模式: ECH-TLS、普通TLS、无TLS 三种代理模式"
    echo "快捷: bash cfsh.sh"
    echo "================================================================"
    echo
    echo "1. 增设 CF-Socks5/Http 节点配置"
    echo "2. 查看某个节点配置信息及日志"
    echo "3. 删除某个节点"
    echo "4. 卸载删除所有配置节点"
    echo "5. 退出"
    echo
    show_installed_nodes
    echo
}

# ============ 主程序 ============

main() {
    # 检查是否为 root 用户（systemd 服务需要）
    if [ "$INIT_SYSTEM" = "systemd" ] && [ "$(id -u)" -ne 0 ]; then
        print_warning "检测到 systemd 环境，建议使用 root 权限运行以创建系统服务"
    fi
    
    while true; do
        show_menu
        
        local choice
        read -p "请选择 [1-5]: " choice
        
        case "$choice" in
            1)
                install_node
                read -p "按回车键继续..." 
                ;;
            2)
                view_node_info
                read -p "按回车键继续..." 
                ;;
            3)
                delete_node
                read -p "按回车键继续..." 
                ;;
            4)
                uninstall_all
                exit 0
                ;;
            5)
                print_info "退出程序"
                exit 0
                ;;
            *)
                print_error "无效选择，请输入 1-5"
                sleep 2
                ;;
        esac
    done
}

# 脚本入口
main
