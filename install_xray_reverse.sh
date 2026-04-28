#!/usr/bin/env bash
# =============================================================================
# Xray-2go 原生反向代理（VMess + WS + CF 专用版）
# 专为套 Cloudflare CDN 设计，支持双路径回源与内网穿透
# =============================================================================

set -euo pipefail

RED='\033[1;91m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
PURPLE='\033[1;35m'
CYAN='\033[1;36m'
BOLD='\033[1m'
RESET='\033[0m'

r()  { echo -e "${RED}$*${RESET}"; }
g()  { echo -e "${GREEN}$*${RESET}"; }
y()  { echo -e "${YELLOW}$*${RESET}"; }
p()  { echo -e "${PURPLE}$*${RESET}"; }
c()  { echo -e "${CYAN}$*${RESET}"; }
b()  { echo -e "${BOLD}$*${RESET}"; }

step()  { echo -e "\n${CYAN}┌─ ${BOLD}[$(printf '%02d' $STEP_NUM)/$STEP_TOTAL]${RESET}${CYAN} $*${RESET}"; STEP_NUM=$((STEP_NUM+1)); }
ok()    { echo -e "${GREEN}└─ ✓ $*${RESET}"; }
info()  { echo -e "${YELLOW}│  $*${RESET}"; }
fail()  { echo -e "${RED}└─ ✗ $*${RESET}" >&2; exit 1; }
warn()  { echo -e "${YELLOW}└─ ⚠ $*${RESET}"; }

STEP_NUM=1
STEP_TOTAL=9

OS_NAME="$(uname -s)"
ARCH_RAW="$(uname -m)"
IS_ROOT=false
[[ $EUID -eq 0 ]] && IS_ROOT=true

WORK_DIR="/etc/xray-rev"
[[ "$IS_ROOT" == "false" ]] && WORK_DIR="$HOME/.local/share/xray-rev"
CONFIG_FILE="${WORK_DIR}/config.json"
XRAY_LOG="${WORK_DIR}/xray.log"

if [[ -n "${TERM:-}" ]]; then
    clear || true
fi

echo -e "${PURPLE}"
cat << 'BANNER'
  ╔═══════════════════════════════════════════════╗
  ║    Xray Reverse Proxy (VMess+WS+CF)           ║
  ║        Intranet Penetration & Secure CDN      ║
  ╚═══════════════════════════════════════════════╝
BANNER
echo -e "${RESET}"

step "选择运行角色"
echo -e "  1) ${CYAN}服务端 (Portal)${RESET} - 公网 VPS (接 CF 回源)"
echo -e "  2) ${CYAN}客户端 (Bridge)${RESET} - 内网主机 (连 CF 域名)"
read -p "请选择 (1/2, 默认 1): " ROLE_CHOICE
ROLE_CHOICE=${ROLE_CHOICE:-1}
ROLE=$([[ "$ROLE_CHOICE" == "1" ]] && echo "portal" || echo "bridge")

step "配置交互"
read -p "请输入 UUID (需两端一致): " UUID
[[ -z "${UUID}" ]] && UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "550e8400-e29b-41d4-a716-446655440000")
read -p "请输入反代内部域名 (默认 reverse.local): " REV_DOMAIN
REV_DOMAIN=${REV_DOMAIN:-reverse.local}

if [[ "$ROLE" == "portal" ]]; then
    read -p "请输入用户访问端口 (对应回源 A, 默认 80): " EXT_PORT
    EXT_PORT=${EXT_PORT:-80}
    read -p "请输入隧道连接端口 (对应回源 B, 默认 8080): " TUNNEL_PORT
    TUNNEL_PORT=${TUNNEL_PORT:-8080}
    read -p "请输入用户访问路径 (默认 /user): " USER_PATH
    USER_PATH=${USER_PATH:-/user}
    read -p "请输入隧道连接路径 (默认 /tunnel): " TUNNEL_PATH
    TUNNEL_PATH=${TUNNEL_PATH:-/tunnel}
else
    read -p "请输入公网服务器 CF 域名: " SERVER_ADDR
    [[ -z "${SERVER_ADDR}" ]] && fail "必须输入域名"
    read -p "请输入隧道连接路径 (需与服务端一致, 默认 /tunnel): " TUNNEL_PATH
    TUNNEL_PATH=${TUNNEL_PATH:-/tunnel}
    read -p "请输入内网服务目标 (默认 127.0.0.1:80): " LOCAL_TARGET
    LOCAL_TARGET=${LOCAL_TARGET:-127.0.0.1:80}
    read -p "是否同时开启本地 SOCKS5 代理？(y/n, 默认 n): " ENABLE_PROXY
    ENABLE_PROXY=${ENABLE_PROXY:-n}
    if [[ "$ENABLE_PROXY" == "y" ]]; then
        read -p "  请输入本地代理端口 (默认 1080): " PROXY_PORT
        PROXY_PORT=${PROXY_PORT:-1080}
    fi
fi

step "检测系统架构"
case "${ARCH_RAW}" in
    'x86_64') XRAY_ASSET="Xray-linux-64.zip" ;;
    'aarch64'|'arm64') XRAY_ASSET="Xray-linux-arm64-v8a.zip" ;;
    *) XRAY_ASSET="Xray-linux-64.zip" ;;
esac

step "下载并安装 Xray"
mkdir -p "${WORK_DIR}"
XRAY_URL="https://github.com/XTLS/Xray-core/releases/latest/download/${XRAY_ASSET}"
curl -fL -o "${WORK_DIR}/xray.zip" "${XRAY_URL}"
unzip -o "${WORK_DIR}/xray.zip" -d "${WORK_DIR}/" > /dev/null 2>&1
chmod +x "${WORK_DIR}/xray"
ok "Xray 安装完成"

step "生成配置文件"
if [[ "$ROLE" == "portal" ]]; then
    # Portal (VMess + WS)
    cat > "${CONFIG_FILE}" << EOF
{
  "log": { "loglevel": "none" },
  "reverse": { "portals": [{ "tag": "portal", "domain": "${REV_DOMAIN}" }] },
  "inbounds": [
    {
      "tag": "ext_traffic", "port": ${EXT_PORT}, "protocol": "vmess",
      "settings": { "clients": [{ "id": "${UUID}", "alterId": 0 }] },
      "streamSettings": { "network": "ws", "wsSettings": { "path": "${USER_PATH}" } }
    },
    {
      "tag": "bridge_tunnel", "port": ${TUNNEL_PORT}, "protocol": "vmess",
      "settings": { "clients": [{ "id": "${UUID}", "alterId": 0 }] },
      "streamSettings": { "network": "ws", "wsSettings": { "path": "${TUNNEL_PATH}" } }
    }
  ],
  "routing": { "rules": [{ "type": "field", "inboundTag": ["ext_traffic"], "outboundTag": "portal" }] },
  "outbounds": [{ "protocol": "freedom", "tag": "direct" }]
}
EOF
else
    # Bridge (VMess + WS + TLS)
    INBOUNDS="[]"
    [[ "$ENABLE_PROXY" == "y" ]] && INBOUNDS="[{ \"port\": ${PROXY_PORT}, \"protocol\": \"socks\", \"settings\": { \"auth\": \"noauth\" }, \"tag\": \"local_proxy\" }]"
    
    cat > "${CONFIG_FILE}" << EOF
{
  "log": { "loglevel": "none" },
  "reverse": { "bridges": [{ "tag": "bridge", "domain": "${REV_DOMAIN}" }] },
  "inbounds": ${INBOUNDS},
  "outbounds": [
    {
      "tag": "tunnel_out", "protocol": "vmess",
      "settings": { "vnext": [{ "address": "${SERVER_ADDR}", "port": 443, "users": [{ "id": "${UUID}", "alterId": 0, "security": "auto" }] }] },
      "streamSettings": { "network": "ws", "security": "tls", "tlsSettings": { "serverName": "${SERVER_ADDR}" }, "wsSettings": { "path": "${TUNNEL_PATH}" } }
    },
    { "tag": "local_service", "protocol": "freedom", "settings": { "redirect": "${LOCAL_TARGET}" } },
    { "tag": "direct", "protocol": "freedom" }
  ],
  "routing": {
    "rules": [
      { "type": "field", "inboundTag": ["bridge"], "outboundTag": "local_service" },
      { "type": "field", "inboundTag": ["local_proxy"], "outboundTag": "direct" },
      { "type": "field", "outboundTag": ["tunnel_out"], "network": "tcp,udp" }
    ]
  }
}
EOF
fi
ok "配置文件已生成"

step "启动服务"
if command -v systemctl >/dev/null 2>&1; then
    if $IS_ROOT; then SVCPATH="/etc/systemd/system"; CMD="systemctl"; else SVCPATH="$HOME/.config/systemd/user"; CMD="systemctl --user"; mkdir -p "$SVCPATH"; fi
    cat > "$SVCPATH/xray-rev.service" << EOF
[Unit]
Description=Xray Reverse Proxy (CF Mode)
After=network.target
[Service]
ExecStart=${WORK_DIR}/xray run -c ${CONFIG_FILE}
Restart=on-failure
[Install]
WantedBy=$( $IS_ROOT && echo "multi-user.target" || echo "default.target" )
EOF
    $CMD daemon-reload && $CMD enable xray-rev --now >/dev/null 2>&1 || true
    $CMD restart xray-rev
fi
ok "服务启动成功"

step "安装完成"
if [[ "$ROLE" == "portal" ]]; then
    echo -e "服务端已就绪。请在 CF 设置回源规则："
    echo -e "  路径 ${CYAN}${USER_PATH}${RESET} -> 端口 ${CYAN}${EXT_PORT}${RESET}"
    echo -e "  路径 ${CYAN}${TUNNEL_PATH}${RESET} -> 端口 ${CYAN}${TUNNEL_PORT}${RESET}"
else
    echo -e "客户端已就绪。穿透目标: ${CYAN}${LOCAL_TARGET}${RESET}"
fi

# 自动清理
[[ -f "$0" && "$0" == *"install_xray_reverse.sh"* ]] && rm -f "$0"
