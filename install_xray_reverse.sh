#!/usr/bin/env bash
# =============================================================================
# Xray-2go 原生反向代理（VMess + WS + CF 专用版）
# 专为套 Cloudflare CDN 设计，支持双路径分流与内网穿透
# =============================================================================

set -euo pipefail

# 颜色定义
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
PURPLE='\033[1;35m'
CYAN='\033[1;36m'
BOLD='\033[1m'
RESET='\033[0m'

# 辅助函数
r()  { echo -e "${RED}$*${RESET}"; }
g()  { echo -e "${GREEN}$*${RESET}"; }
y()  { echo -e "${YELLOW}$*${RESET}"; }
b()  { echo -e "${BLUE}$*${RESET}"; }
p()  { echo -e "${PURPLE}$*${RESET}"; }
c()  { echo -e "${CYAN}$*${RESET}"; }

step()  { echo -e "\n${CYAN}┌─ ${BOLD}[$STEP_NUM]${RESET}${CYAN} $*${RESET}"; STEP_NUM=$((STEP_NUM+1)); }
ok()    { echo -e "${GREEN}└─ ✓ $*${RESET}"; }
info()  { echo -e "${YELLOW}│  $*${RESET}"; }
fail()  { echo -e "${RED}└─ ✗ $*${RESET}" >&2; exit 1; }

STEP_NUM=1
IS_ROOT=false
[[ $EUID -eq 0 ]] && IS_ROOT=true

# 目录与路径
WORK_DIR="/etc/xray-rev"
[[ "$IS_ROOT" == "false" ]] && WORK_DIR="$HOME/.local/share/xray-rev"
CONFIG_FILE="${WORK_DIR}/config.json"
XRAY_BIN="${WORK_DIR}/xray"

# 检查权限与 systemd
HAS_SYSTEMD=false
command -v systemctl >/dev/null 2>&1 && HAS_SYSTEMD=true
SYSTEMCTL_CMD="systemctl"
[[ "$IS_ROOT" == "false" ]] && SYSTEMCTL_CMD="systemctl --user"

# -----------------------------------------------------------------------------
# 核心逻辑：安装组件
# -----------------------------------------------------------------------------

install_xray() {
    step "下载并安装 Xray-core"
    mkdir -p "${WORK_DIR}"
    ARCH_RAW="$(uname -m)"
    case "${ARCH_RAW}" in
        'x86_64') XRAY_ASSET="Xray-linux-64.zip" ;;
        'aarch64'|'arm64') XRAY_ASSET="Xray-linux-arm64-v8a.zip" ;;
        *) XRAY_ASSET="Xray-linux-64.zip" ;;
    esac
    
    URL="https://github.com/XTLS/Xray-core/releases/latest/download/${XRAY_ASSET}"
    curl -fL -o "${WORK_DIR}/xray.zip" "${URL}"
    unzip -o "${WORK_DIR}/xray.zip" -d "${WORK_DIR}/" > /dev/null 2>&1
    chmod +x "${XRAY_BIN}"
    rm -f "${WORK_DIR}/xray.zip"
    ok "Xray 安装完成"
}

setup_service() {
    step "配置系统服务"
    if $HAS_SYSTEMD; then
        if $IS_ROOT; then SVCPATH="/etc/systemd/system"; else SVCPATH="$HOME/.config/systemd/user"; mkdir -p "$SVCPATH"; fi
        cat > "$SVCPATH/xray-rev.service" << EOF
[Unit]
Description=Xray Reverse Proxy (CF Mode)
After=network.target

[Service]
ExecStart=${XRAY_BIN} run -c ${CONFIG_FILE}
Restart=on-failure

[Install]
WantedBy=$( $IS_ROOT && echo "multi-user.target" || echo "default.target" )
EOF
        $SYSTEMCTL_CMD daemon-reload
        $SYSTEMCTL_CMD enable xray-rev --now >/dev/null 2>&1 || true
        $SYSTEMCTL_CMD restart xray-rev
        ok "服务已启动并设为开机自启"
    else
        pkill -f "${XRAY_BIN}" || true
        "${XRAY_BIN}" run -c "${CONFIG_FILE}" > /dev/null 2>&1 &
        ok "服务已在后台启动"
    fi
}

# -----------------------------------------------------------------------------
# 功能模块：服务端
# -----------------------------------------------------------------------------

install_portal() {
    c "\n--- 安装服务端 (Portal) ---"
    read -p "请输入 UUID (留空随机): " UUID
    UUID=${UUID:-$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "550e8400-e29b-41d4-a716-446655440000")}
    RANDOM_PORT=$(awk 'BEGIN { srand(); print int(10000 + rand() * 50000) }')
    read -p "请输入监听端口 (默认 ${RANDOM_PORT}): " LISTEN_PORT
    LISTEN_PORT=${LISTEN_PORT:-${RANDOM_PORT}}
    read -p "请输入用户访问路径 (默认 /user): " USER_PATH
    USER_PATH=${USER_PATH:-/user}
    read -p "请输入隧道连接路径 (默认 /tunnel): " TUNNEL_PATH
    TUNNEL_PATH=${TUNNEL_PATH:-/tunnel}
    
    install_xray
    
    cat > "${CONFIG_FILE}" << EOF
{
  "log": { "loglevel": "none" },
  "reverse": { "portals": [{ "tag": "portal", "domain": "reverse.local" }] },
  "inbounds": [
    {
      "port": ${LISTEN_PORT}, "protocol": "vmess",
      "settings": { "clients": [{ "id": "${UUID}", "alterId": 0 }] },
      "streamSettings": { "network": "ws" }
    }
  ],
  "routing": {
    "rules": [
      { "type": "field", "path": ["${USER_PATH}"], "outboundTag": "portal" },
      { "type": "field", "path": ["${TUNNEL_PATH}"], "outboundTag": "direct" }
    ]
  },
  "outbounds": [{ "protocol": "freedom", "tag": "direct" }]
}
EOF
    setup_service
    g "\n✅ 服务端安装完成！"
    echo -e "请在 Cloudflare Origin Rules 中配置转发："
    echo -e "  路径 ${CYAN}${USER_PATH}${RESET} -> 端口 ${CYAN}${LISTEN_PORT}${RESET}"
    echo -e "  路径 ${CYAN}${TUNNEL_PATH}${RESET} -> 端口 ${CYAN}${LISTEN_PORT}${RESET}"
    echo -e "UUID: ${PURPLE}${UUID}${RESET}"
}

# -----------------------------------------------------------------------------
# 功能模块：客户端
# -----------------------------------------------------------------------------

install_bridge() {
    c "\n--- 安装客户端 (Bridge) ---"
    read -p "请输入 UUID: " UUID
    [[ -z "${UUID}" ]] && fail "必须输入 UUID"
    read -p "请输入公网服务器 CF 域名: " SERVER_ADDR
    [[ -z "${SERVER_ADDR}" ]] && fail "必须输入域名"
    read -p "请输入隧道连接路径 (默认 /tunnel): " TUNNEL_PATH
    TUNNEL_PATH=${TUNNEL_PATH:-/tunnel}
    
    echo -e "\n请选择客户端工作模式:"
    echo -e "  1) ${CYAN}转发模式${RESET} - 将流量转发到本地特定服务 (如 Web)"
    echo -e "  2) ${CYAN}出口模式${RESET} - 将客户端作为上网出口 (访问 YouTube 等)"
    read -p "请选择 (1/2, 默认 1): " BRIDGE_MODE
    BRIDGE_MODE=${BRIDGE_MODE:-1}
    
    if [[ "$BRIDGE_MODE" == "1" ]]; then
        read -p "请输入内网服务目标 (默认 127.0.0.1:80): " LOCAL_TARGET
        LOCAL_TARGET=${LOCAL_TARGET:-127.0.0.1:80}
        OUTBOUND_SETTINGS="{\"redirect\": \"${LOCAL_TARGET}\"}"
    else
        OUTBOUND_SETTINGS="{}"
        info "已选择出口模式，流量将直接发往互联网"
    fi
    
    install_xray
    
    cat > "${CONFIG_FILE}" << EOF
{
  "log": { "loglevel": "none" },
  "reverse": { "bridges": [{ "tag": "bridge", "domain": "reverse.local" }] },
  "outbounds": [
    {
      "tag": "tunnel_out", "protocol": "vmess",
      "settings": { "vnext": [{ "address": "${SERVER_ADDR}", "port": 443, "users": [{ "id": "${UUID}", "alterId": 0, "security": "aes-128-gcm" }] }] },
      "streamSettings": { "network": "ws", "security": "tls", "tlsSettings": { "serverName": "${SERVER_ADDR}" }, "wsSettings": { "path": "${TUNNEL_PATH}" } }
    },
    { "tag": "local_service", "protocol": "freedom", "settings": ${OUTBOUND_SETTINGS} },
    { "tag": "direct", "protocol": "freedom" }
  ],
  "routing": {
    "rules": [
      { "type": "field", "inboundTag": ["bridge"], "outboundTag": "local_service" },
      { "type": "field", "outboundTag": ["tunnel_out"], "network": "tcp,udp" }
    ]
  },
  "sniffing": { "enabled": true, "destOverride": ["http", "tls"] }
}
EOF
    setup_service
    g "\n✅ 客户端安装完成！"
    echo -e "已通过域名 ${CYAN}${SERVER_ADDR}${RESET} 建立隧道"
    echo -e "内网目标: ${CYAN}${LOCAL_TARGET}${RESET}"
}

# -----------------------------------------------------------------------------
# 辅助模块：管理
# -----------------------------------------------------------------------------

show_status() {
    if $HAS_SYSTEMD; then
        $SYSTEMCTL_CMD status xray-rev --no-pager || y "服务未运行"
    else
        pgrep -f "${XRAY_BIN}" > /dev/null && g "Xray 正在运行" || r "Xray 已停止"
    fi
}

uninstall() {
    read -p "确定要卸载吗？(y/n): " confirm
    [[ "$confirm" != "y" ]] && return
    if $HAS_SYSTEMD; then
        $SYSTEMCTL_CMD stop xray-rev >/dev/null 2>&1 || true
        $SYSTEMCTL_CMD disable xray-rev >/dev/null 2>&1 || true
        if $IS_ROOT; then rm -f /etc/systemd/system/xray-rev.service; else rm -f "$HOME/.config/systemd/user/xray-rev.service"; fi
        $SYSTEMCTL_CMD daemon-reload
    fi
    pkill -f "${XRAY_BIN}" || true
    rm -rf "${WORK_DIR}"
    g "卸载成功！"
}

# -----------------------------------------------------------------------------
# 主菜单
# -----------------------------------------------------------------------------

main_menu() {
    clear
    p "================================================="
    p "    Xray 原生反代 (VMess+WS+CF) 一键管理脚本     "
    p "================================================="
    echo -e "  1) ${GREEN}安装服务端 (Portal)${RESET}"
    echo -e "  2) ${GREEN}安装客户端 (Bridge)${RESET}"
    echo -e "  3) ${BLUE}查看运行状态${RESET}"
    echo -e "  4) ${YELLOW}添加新客户端配置 (仅服务端)${RESET}"
    echo -e "  5) ${PURPLE}管理 VMess 端口映射 (仅服务端)${RESET}"
    echo -e "  6) ${RED}一键卸载${RESET}"
    echo -e "  0) 退出"
    echo -e "-------------------------------------------------"
    read -p "请输入选项: " choice
    
    case "$choice" in
        1) install_portal ;;
        2) install_bridge ;;
        3) show_status ;;
        4) add_portal_client ;;
        5) manage_vmess_mapping ;;
        6) uninstall ;;
        *) exit 0 ;;
    esac
}

# -----------------------------------------------------------------------------
# 高级功能：在服务端增加新客户端
# -----------------------------------------------------------------------------

add_portal_client() {
    [[ ! -f "$CONFIG_FILE" ]] && fail "未找到配置文件，请先安装服务端"
    [[ "$(grep -c "bridges" "$CONFIG_FILE")" -gt 0 ]] && fail "当前设备是客户端角色，无法添加服务端配置"

    c "\n--- 为服务端添加新客户端 ---"
    read -p "请输入新客户端的识别域名 (如 reverse2.local): " NEW_REV_DOMAIN
    [[ -z "${NEW_REV_DOMAIN}" ]] && fail "必须输入域名"
    read -p "请输入该客户端的用户访问路径 (如 /user2): " NEW_USER_PATH
    [[ -z "${NEW_USER_PATH}" ]] && fail "必须输入路径"
    
    NEW_TAG="portal_$(date +%s)"
    
    # 使用 jq 动态修改配置
    tmp_config="${CONFIG_FILE}.tmp"
    jq ".reverse.portals += [{\"tag\": \"${NEW_TAG}\", \"domain\": \"${NEW_REV_DOMAIN}\"}] | 
        .routing.rules = [{\"type\": \"field\", \"path\": [\"${NEW_USER_PATH}\"], \"outboundTag\": \"${NEW_TAG}\"}] + .routing.rules" \
        "$CONFIG_FILE" > "$tmp_config" && mv "$tmp_config" "$CONFIG_FILE"

    $SYSTEMCTL_CMD restart xray-rev
    g "\n✅ 客户端添加成功！"
    echo -e "新服务路径: ${CYAN}${NEW_USER_PATH}${RESET}"
    echo -e "匹配域名: ${CYAN}${NEW_REV_DOMAIN}${RESET}"
    echo -e "请在内网客户端安装时使用相同的识别域名。"
}

# -----------------------------------------------------------------------------
# 映射管理：VMess 端口 -> 客户端标签
# -----------------------------------------------------------------------------

manage_vmess_mapping() {
    [[ ! -f "$CONFIG_FILE" ]] && fail "未找到配置文件"
    
    echo -e "\n--- VMess 端口映射管理 ---"
    echo -e "  1) 添加新端口映射"
    echo -e "  2) 查看当前映射列表"
    echo -e "  3) 删除端口映射"
    echo -e "  0) 返回主菜单"
    read -p "选择操作: " sub_choice
    
    case "$sub_choice" in
        1)
            # 列出可选客户端
            echo -e "\n可用客户端列表:"
            jq -r '.reverse.portals[] | "- \(.domain) (tag: \(.tag))"' "$CONFIG_FILE"
            read -p "请输入要映射的客户端识别域名: " TARGET_DOMAIN
            TARGET_TAG=$(jq -r ".reverse.portals[] | select(.domain==\"$TARGET_DOMAIN\") | .tag" "$CONFIG_FILE")
            [[ -z "$TARGET_TAG" ]] && fail "找不到该客户端"
            
            read -p "请输入新 VMess 端口: " NEW_PORT
            read -p "请输入该端口的 UUID (留空使用全局): " NEW_UUID
            GLOBAL_UUID=$(jq -r '.inbounds[0].settings.clients[0].id' "$CONFIG_FILE")
            NEW_UUID=${NEW_UUID:-$GLOBAL_UUID}
            
            MAP_TAG="map_${NEW_PORT}"
            
            # 增加入站和路由
            tmp_config="${CONFIG_FILE}.tmp"
            jq ".inbounds += [{\"tag\": \"${MAP_TAG}\", \"port\": ${NEW_PORT}, \"protocol\": \"vmess\", \"settings\": {\"clients\": [{\"id\": \"${NEW_UUID}\", \"alterId\": 0}]}}] |
                .routing.rules = [{\"type\": \"field\", \"inboundTag\": [\"${MAP_TAG}\"], \"outboundTag\": \"${TARGET_TAG}\"}] + .routing.rules" \
                "$CONFIG_FILE" > "$tmp_config" && mv "$tmp_config" "$CONFIG_FILE"
            
            $SYSTEMCTL_CMD restart xray-rev
            g "✅ 映射添加成功！端口 ${NEW_PORT} -> 客户端 ${TARGET_DOMAIN}"
            ;;
        2)
            echo -e "\n当前 VMess 端口映射列表:"
            jq -r '.routing.rules[] | select(.inboundTag != null) | "端口: \(.inboundTag[0]) -> 目标标签: \(.outboundTag)"' "$CONFIG_FILE" | sed 's/map_//g'
            read -p "按回车继续..."
            ;;
        3)
            read -p "请输入要删除映射的端口号: " DEL_PORT
            MAP_TAG="map_${DEL_PORT}"
            tmp_config="${CONFIG_FILE}.tmp"
            jq "del(.inbounds[] | select(.tag == \"${MAP_TAG}\")) | 
                del(.routing.rules[] | select(.inboundTag != null and .inboundTag[0] == \"${MAP_TAG}\"))" \
                "$CONFIG_FILE" > "$tmp_config" && mv "$tmp_config" "$CONFIG_FILE"
            
            $SYSTEMCTL_CMD restart xray-rev
            g "✅ 映射端口 ${DEL_PORT} 已删除"
            ;;
        *) return ;;
    esac
}

# 检查环境并启动
command -v curl &>/dev/null || fail "缺少 curl，请先安装"
command -v unzip &>/dev/null || fail "缺少 unzip，请先安装"
command -v jq &>/dev/null || (if $IS_ROOT; then apt-get update -qq && apt-get install -y -qq jq; else fail "缺少 jq，请先安装"; fi)

main_menu
