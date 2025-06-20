#!/bin/bash
## Author: X_ni_dada
## Modified: 2025-06-20
## GitHub: https://github.com/Xnidada/​​pge-installer
# 错误处理：任何命令失败则退出脚本
set -euo pipefail

# 全局配置
LOCAL_IP=""
PROMETHEUS_CONF_DIR="$(pwd)/prometheus"
PROMETHEUS_CONF_FILE="${PROMETHEUS_CONF_DIR}/prometheus.yml"
NODE_EXPORTER_VERSION="1.9.1"

# 获取本机IP地址（兼容更多系统）
get_local_ip() {
  ip_command() {
    # 尝试多种方法获取IP
    { ip -4 route get 1 | awk '{print $7}'; } || 
    { hostname -I | awk '{print $1}'; } || 
    { ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | head -n1; }
  }

  LOCAL_IP=$(ip_command)
  if [ -z "$LOCAL_IP" ]; then
    echo -e "\e[31mERROR: 无法获取本机IP地址，请手动设置\e[0m" >&2
    return 1
  fi
}

# 安装依赖命令
ensure_commands() {
  local missing=()
  for cmd in "$@"; do
    if ! command -v "$cmd" &> /dev/null; then
      missing+=("$cmd")
    fi
  done
  
  if [ ${#missing[@]} -gt 0 ]; then
    echo -e "\e[31m错误：需要安装缺失的命令: ${missing[*]}\e[0m" >&2
    return 1
  fi
}

# 换源函数
change_sources() {
  echo "正在更换系统软件源为国内镜像..."
  curl -fsSL https://github.com/Xnidada/LinuxMirrors-NoAD/blob/main/ChangeMirrors.sh | bash
  
  echo "正在更换 Docker 软件源..."
  curl -fsSL https://github.com/Xnidada/LinuxMirrors-NoAD/blob/main/DockerInstallation.sh | bash
}

# 生成初始配置
generate_prometheus_config() {
  # 避免覆盖已有配置
  if [[ -f "$PROMETHEUS_CONF_FILE" ]]; then
    read -r -p "配置文件已存在，是否覆盖? (y/n) " overwrite
    if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
      echo "跳过配置文件生成"
      return 0
    fi
  fi

  # 配置参数
  local SCRAPE_INTERVAL EVALUATION_INTERVAL
  while true; do
    read -r -p "采集周期 (s, 默认15): " SCRAPE_INTERVAL
    SCRAPE_INTERVAL=${SCRAPE_INTERVAL:-15}
    
    if [[ "$SCRAPE_INTERVAL" =~ ^[0-9]+$ ]]; then
      break
    else
      echo -e "\e[31m错误：请输入有效数字\e[0m"
    fi
  done

  while true; do
    read -r -p "告警评估周期 (s, 默认15): " EVALUATION_INTERVAL
    EVALUATION_INTERVAL=${EVALUATION_INTERVAL:-15}
    
    if [[ "$EVALUATION_INTERVAL" =~ ^[0-9]+$ ]]; then
      break
    else
      echo -e "\e[31m错误：请输入有效数字\e[0m"
    fi
  done

  # 确保配置目录存在
  mkdir -p "$PROMETHEUS_CONF_DIR"
  
  # 生成配置文件
  cat << EOF > "$PROMETHEUS_CONF_FILE"
global:
  scrape_interval:     ${SCRAPE_INTERVAL}s
  evaluation_interval: ${EVALUATION_INTERVAL}s
alerting:
  alertmanagers:
  - static_configs:
    - targets: []
rule_files: []
scrape_configs:
  - job_name: 'prometheus'
    static_configs:
    - targets: ['${LOCAL_IP}:9090']
EOF

  echo -e "\e[32mPrometheus 配置文件已生成: ${PROMETHEUS_CONF_FILE}\e[0m"
}

# 添加监控节点
add_prometheus_config() {
  # 检查配置是否存在
  if [[ ! -f "$PROMETHEUS_CONF_FILE" ]]; then
    echo -e "\e[31m错误：未找到配置文件，请先生成配置\e[0m" >&2
    return 1
  fi

  echo -e "\n\e[34m当前配置的监控节点:\e[0m"
  grep -A5 'static_configs:' "$PROMETHEUS_CONF_FILE" | grep -oP "(?<=targets: \[')[^]]*"

  local JOB_NAME NODE_EX_IP
  while true; do
    read -r -p "节点显示名称: " JOB_NAME
    [[ -n "$JOB_NAME" ]] && break || echo "名称不能为空"
  done

  while true; do
    read -r -p "监控地址 (IP:9100): " NODE_EX_IP
    if [[ "$NODE_EX_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:9100$ ]]; then
      break
    else
      echo -e "\e[31m格式错误，应为X.X.X.X:9100\e[0m"
    fi
  done

  # 避免重复添加
  if grep -q "'$NODE_EX_IP'" "$PROMETHEUS_CONF_FILE"; then
    echo "该节点已在配置中"
    return 0
  fi

  # 添加节点到配置
  cat << EOF >> "$PROMETHEUS_CONF_FILE"
  - job_name: '${JOB_NAME}'
    static_configs:
    - targets: ['${NODE_EX_IP}']
EOF

  echo -e "\e[32m节点添加成功\e[0m"
  echo -e "\n\e[34m更新后的监控节点:\e[0m"
  grep -A5 'static_configs:' "$PROMETHEUS_CONF_FILE" | grep -oP "(?<=targets: \[')[^]]*"
}

# 安装Grafana
install_grafana() {
  if docker inspect grafana &>/dev/null; then
    echo "Grafana 已在运行中"
    return 0
  fi

  docker run -d --name=grafana -p 3000:3000 \
    -e "GF_SECURITY_ADMIN_PASSWORD=monitor@123" \
    grafana/grafana
  
  echo -e "\e[32mGrafana 已启动\e[0m"
  echo -e "URL: http://${LOCAL_IP}:3000"
  echo -e "用户名: admin"
  echo -e "密码: \e[31mmonitor@123\e[0m (建议登录后修改)"
}

# 安装node_exporter
install_node_exporter() {
  # 检查是否已安装
  if systemctl is-active --quiet node_exporter; then
    echo "node_exporter 服务已在运行"
    return 0
  elif command -v node_exporter &>/dev/null; then
    echo "node_exporter 已安装但未运行，尝试启动..."
    sudo systemctl enable --now node_exporter || return 1
    return 0
  fi

  ensure_commands curl || return 1

  echo "安装 Node Exporter v${NODE_EXPORTER_VERSION} ..."
  
  # 临时目录
  local TEMP_DIR
  TEMP_DIR=$(mktemp -d)
  
  # 下载解压
  curl -fLsS -o "$TEMP_DIR/node_exporter.tar.gz" \
    "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
  
  tar -xzf "$TEMP_DIR/node_exporter.tar.gz" -C "$TEMP_DIR"
  
  # 安装二进制
  sudo install -m 755 "$TEMP_DIR/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter" /usr/local/bin/

  # 创建系统服务
  cat << EOF | sudo tee /usr/lib/systemd/system/node_exporter.service >/dev/null
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
ExecStart=/usr/local/bin/node_exporter
Restart=always
RestartSec=3
User=node_exporter
Group=node_exporter

[Install]
WantedBy=multi-user.target
EOF

  # 创建专用用户
  if ! id node_exporter &>/dev/null; then
    sudo useradd -rs /bin/false node_exporter
  fi

  # 启动服务
  sudo systemctl daemon-reload
  sudo systemctl enable --now node_exporter >/dev/null

  # 清理
  rm -rf "$TEMP_DIR"
  
  echo -e "\e[32mNode Exporter 安装成功\e[0m"
  echo -e "指标地址: http://${LOCAL_IP}:9100/metrics"
}

# 安装Prometheus
install_prometheus() {
  # 检查配置文件是否存在
  if [[ ! -f "$PROMETHEUS_CONF_FILE" ]]; then
    echo -e "\e[31m错误：未找到配置文件，请先生成配置\e[0m" >&2
    return 1
  fi

  # 停止旧容器
  if docker ps -a --format "{{.Names}}" | grep -q "^prometheus$"; then
    echo "停止现有Prometheus容器..."
    docker stop prometheus >/dev/null
    docker rm prometheus >/dev/null
  fi

  # 启动新容器
  docker run -d \
    --name=prometheus \
    -p 9090:9090 \
    --restart=unless-stopped \
    -v "$PROMETHEUS_CONF_FILE:/etc/prometheus/prometheus.yml" \
    prom/prometheus \
    --config.file=/etc/prometheus/prometheus.yml \
    --web.enable-lifecycle

  echo -e "\e[32mPrometheus 启动完成\e[0m"
  echo -e "管理界面: http://${LOCAL_IP}:9090"
  echo -e "重载配置: curl -X POST http://${LOCAL_IP}:9090/-/reload"
}

# 打印菜单
print_menu() {
  clear
  echo "=== Prometheus 监控系统部署 ==="
  echo "本机 IP: ${LOCAL_IP:-未获取}"
  echo "配置文件: ${PROMETHEUS_CONF_FILE}"
  echo
  echo "1) 更换系统源和Docker源"
  echo "2) 生成Prometheus配置文件"
  echo "3) 安装与启动Grafana"
  echo "4) 被监控节点安装Node Exporter"
  echo "5) 添加被监控节点"
  echo "6) 安装与启动Prometheus"
  echo "7) 一键部署监控节点 (执行1,2,3,6)"
  echo "8) 一键部署被监控节点 (执行1,4)"
  echo "s) 显示服务状态"
  echo "c) 检测依赖命令"
  echo "q) 退出"
  echo
}

# 显示服务状态
show_status() {
  echo -e "\n\e[1;34m==== 服务状态 ====\e[0m"
  
  # Docker容器状态
  local containers=("prometheus" "grafana")
  printf "%-12s %-8s %s\n" "容器" "状态" "端口"
  for c in "${containers[@]}"; do
    local status
    if container_id=$(docker ps -a --filter "name=^${c}$" --format '{{.Status}}|{{.Ports}}' 2>/dev/null); then
      IFS='|' read -r status ports <<< "$container_id"
      printf "%-12s \e[32m%-8s\e[0m %s\n" "$c" "$status" "$ports"
    else
      printf "%-12s \e[31m%-8s\e[0m\n" "$c" "未运行"
    fi
  done
  
  # Node Exporter
  echo -ne "\nNode Exporter: "
  if systemctl is-active node_exporter &>/dev/null; then
    echo -e "\e[32m运行中\e[0m (端口:9100)"
  else
    echo -e "\e[31m未运行\e[0m"
  fi
  
  # 配置文件状态
  echo -e "\n配置文件: $PROMETHEUS_CONF_FILE"
  if [[ -f "$PROMETHEUS_CONF_FILE" ]]; then
    echo -e "监控节点数量: $(grep -c 'static_configs:' "$PROMETHEUS_CONF_FILE")"
  else
    echo -e "状态: \e[31m未生成\e[0m"
  fi
}

# 主流程
main() {
  # 初始化获取IP
  if ! get_local_ip; then
    read -r -p "输入本机IP地址: " LOCAL_IP
  fi

  while true; do
    print_menu
    read -r -p "请选择操作: " OPTION
    
    case "$OPTION" in
      1) change_sources ;;
      2) generate_prometheus_config ;;
      3) install_grafana ;;
      4) install_node_exporter ;;
      5) add_prometheus_config ;;
      6) install_prometheus ;;
      7)
        change_sources
        generate_prometheus_config
        install_grafana
        install_prometheus
        ;;
      8)
        change_sources
        install_node_exporter
        ;;
      s) show_status ;;
      c) ensure_commands curl docker systemctl ip ;;
      q) 
        echo "退出脚本"
        exit 0
        ;;
      *)
        echo "无效选项"
        ;;
    esac
    
    read -r -p "按Enter键继续..."
  done
}

# 启动主程序
main