#!/usr/bin/env bash
# =============================================================================
# Xray-2go + Argo 临时隧道 一键安装脚本（无交互）
# 支持: macOS (arm64/x86_64), Linux (amd64/arm64/armv7/386/s390x)
# 用途: 自动安装 Xray-core + cloudflared，生成 VLESS/VMess 节点信息
# =============================================================================

set -euo pipefail

# ─── 颜色 ────────────────────────────────────────────────────────────────────
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
STEP_TOTAL=10

# ─── 基本检测 ────────────────────────────────────────────────────────────────
OS_NAME="$(uname -s)"
ARCH_RAW="$(uname -m)"
IS_MACOS=false

[[ "${OS_NAME}" == "Darwin" ]] && IS_MACOS=true

# root 检查
if [[ $EUID -ne 0 ]]; then
    r "错误：请以 root 权限运行此脚本"
    r "macOS 请用: sudo bash install_argo.sh"
    r "Linux  请用: sudo bash install_argo.sh"
    exit 1
fi

# ─── 目录 & 常量 ─────────────────────────────────────────────────────────────
if $IS_MACOS; then
    WORK_DIR="/usr/local/etc/xray"
    BIN_PATH="/usr/local/bin/2go"
else
    WORK_DIR="/etc/xray"
    BIN_PATH="/usr/bin/2go"
fi

CONFIG_FILE="${WORK_DIR}/config.json"
URL_FILE="${WORK_DIR}/url.txt"
SUB_FILE="${WORK_DIR}/sub.txt"
ARGO_LOG="${WORK_DIR}/argo.log"
XRAY_LOG="${WORK_DIR}/xray.log"

ARGO_PORT=8080   # xray 对外监听（Argo 入口）

# ─── 打印 Banner ─────────────────────────────────────────────────────────────
clear
echo -e "${PURPLE}"
cat << 'BANNER'
  ╔═══════════════════════════════════════════════╗
  ║     Xray-2go + Argo 临时隧道  一键安装        ║
  ║     VLESS / VMess · Reality · WebSocket       ║
  ╚═══════════════════════════════════════════════╝
BANNER
echo -e "${RESET}"
echo -e "  系统 : ${CYAN}${OS_NAME} / ${ARCH_RAW}${RESET}"
echo -e "  目录 : ${CYAN}${WORK_DIR}${RESET}"
echo -e "  时间 : ${CYAN}$(date '+%Y-%m-%d %H:%M:%S')${RESET}"
echo ""

# ─── 工具函数 ────────────────────────────────────────────────────────────────
# 跨平台 base64 不换行
base64_nowrap() {
    if base64 --help 2>&1 | grep -q -- '-w'; then
        base64 -w0 "$@"
    else
        base64 "$@" | tr -d '\n'
    fi
}

# 跨平台 sed -i
sed_inplace() {
    local expr="$1"; shift
    if $IS_MACOS; then
        sed -i '' "$expr" "$@"
    else
        sed -i "$expr" "$@"
    fi
}

# 生成 UUID
gen_uuid() {
    if command -v uuidgen &>/dev/null; then
        uuidgen | tr '[:upper:]' '[:lower:]'
    else
        cat /proc/sys/kernel/random/uuid
    fi
}

# 随机端口
random_port() {
    if command -v shuf &>/dev/null; then
        shuf -i 10000-60000 -n 1
    elif command -v jot &>/dev/null; then
        jot -r 1 10000 60000
    else
        awk 'BEGIN { srand(); print int(10000 + rand() * 50000) }'
    fi
}

# 带进度条的下载（支持自动切换镜像）
download_with_progress() {
    local url="$1"
    local output="$2"
    local label="$3"
    local tmp_file="${output}.tmp"

    info "下载: ${label}"

    # 下载源列表：直连优先，失败后自动切换国内加速镜像
    local sources=(
        "${url}"
        "https://ghfast.top/${url}"
        "https://ghproxy.com/${url}"
        "https://github.moeyy.xyz/${url}"
        "https://p.ff11.tk/${url}"
    )

    local attempt=0
    for src_url in "${sources[@]}"; do
        attempt=$((attempt + 1))
        rm -f "$tmp_file"

        if [[ $attempt -eq 1 ]]; then
            info "尝试 [${attempt}/${#sources[@]}] 直连 GitHub"
        else
            local mirror_host
            mirror_host=$(echo "$src_url" | awk -F/ '{print $3}')
            info "尝试 [${attempt}/${#sources[@]}] 镜像: ${mirror_host}"
        fi

        # --speed-limit 5120 --speed-time 20
        # 若连续 20 秒内平均速率低于 5 KB/s，判定超时并中断，尝试下一个源
        # 比固定 --max-time 更智能：网速快时不误杀，网速慢时尽早切换
        if curl -fL \
            --progress-bar \
            --connect-timeout 15 \
            --speed-limit 5120 \
            --speed-time 20 \
            -o "$tmp_file" \
            "$src_url" 2>/dev/tty; then
            mv "$tmp_file" "$output"
            local size
            size=$(du -sh "$output" 2>/dev/null | cut -f1)
            ok "${label} 下载完成 (${size})"
            return 0
        fi

        warn "下载失败，尝试下一个源..."
    done

    rm -f "$tmp_file"
    fail "${label} 所有下载源均失败，请检查网络连接"
}

# ─── Step 1: 检测架构并选择下载包 ───────────────────────────────────────────
step "检测系统架构"

XRAY_ASSET=""
ARGO_ASSET=""

if $IS_MACOS; then
    case "${ARCH_RAW}" in
        'x86_64')
            XRAY_ASSET="Xray-macos-64.zip"
            ARGO_ASSET="cloudflared-darwin-amd64.tgz"
            ;;
        'arm64' | 'aarch64')
            XRAY_ASSET="Xray-macos-arm64-v8a.zip"
            ARGO_ASSET="cloudflared-darwin-arm64.tgz"
            ;;
        *)
            fail "macOS 暂不支持该架构: ${ARCH_RAW}"
            ;;
    esac
else
    case "${ARCH_RAW}" in
        'x86_64')         XRAY_ASSET="Xray-linux-64.zip";         ARGO_ASSET="cloudflared-linux-amd64" ;;
        'aarch64'|'arm64') XRAY_ASSET="Xray-linux-arm64-v8a.zip"; ARGO_ASSET="cloudflared-linux-arm64" ;;
        'armv7l')         XRAY_ASSET="Xray-linux-arm32-v7a.zip";   ARGO_ASSET="cloudflared-linux-armhf" ;;
        'i386'|'i686')    XRAY_ASSET="Xray-linux-32.zip";          ARGO_ASSET="cloudflared-linux-386" ;;
        's390x')          XRAY_ASSET="Xray-linux-s390x.zip";       ARGO_ASSET="cloudflared-linux-s390x" ;;
        *)                fail "暂不支持的架构: ${ARCH_RAW}" ;;
    esac
fi

info "系统平台 : $($IS_MACOS && echo macOS || echo Linux)"
info "CPU 架构 : ${ARCH_RAW}"
info "Xray 包  : ${XRAY_ASSET}"
info "Argo 包  : ${ARGO_ASSET}"
ok "架构检测完成"

# ─── Step 2: 安装必要依赖 (Linux only) ──────────────────────────────────────
step "检查并安装依赖"

if $IS_MACOS; then
    # macOS 内置 curl、unzip，检查即可
    for cmd in curl unzip jq; do
        if command -v "$cmd" &>/dev/null; then
            info "${cmd} ✓ ($(command -v "$cmd"))"
        else
            if [[ "$cmd" == "jq" ]]; then
                warn "jq 未安装，请先运行: brew install jq"
                warn "继续安装，但 change_config 功能可能受限"
            else
                fail "依赖 ${cmd} 未找到，请手动安装"
            fi
        fi
    done
else
    PKGS_NEEDED=()
    for pkg in curl unzip jq; do
        command -v "$pkg" &>/dev/null || PKGS_NEEDED+=("$pkg")
    done

    if [[ ${#PKGS_NEEDED[@]} -gt 0 ]]; then
        info "需要安装: ${PKGS_NEEDED[*]}"
        if command -v apt &>/dev/null; then
            DEBIAN_FRONTEND=noninteractive apt-get update -qq
            DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${PKGS_NEEDED[@]}"
        elif command -v dnf &>/dev/null; then
            dnf install -y -q "${PKGS_NEEDED[@]}"
        elif command -v yum &>/dev/null; then
            yum install -y -q "${PKGS_NEEDED[@]}"
        elif command -v apk &>/dev/null; then
            apk add --quiet "${PKGS_NEEDED[@]}"
        else
            fail "无法识别的包管理器，请手动安装: ${PKGS_NEEDED[*]}"
        fi
    fi
fi

ok "依赖检查完成"

# ─── Step 3: 准备目录 ────────────────────────────────────────────────────────
step "准备安装目录"

# 停止旧进程（如果有）
if $IS_MACOS; then
    pkill -f "${WORK_DIR}/xray run" &>/dev/null || true
    pkill -f "${WORK_DIR}/argo tunnel" &>/dev/null || true
    info "已停止旧 xray / argo 进程"
else
    systemctl stop xray 2>/dev/null || true
    systemctl stop tunnel 2>/dev/null || true
    info "已停止旧 systemd 服务"
fi

mkdir -p "${WORK_DIR}"
chmod 755 "${WORK_DIR}"
info "安装目录 : ${WORK_DIR}"
ok "目录准备完成"

# ─── Step 4: 下载 Xray-core ─────────────────────────────────────────────────
step "下载 Xray-core"

XRAY_URL="https://github.com/XTLS/Xray-core/releases/latest/download/${XRAY_ASSET}"
XRAY_ZIP="${WORK_DIR}/xray.zip"

download_with_progress "$XRAY_URL" "$XRAY_ZIP" "Xray-core (${XRAY_ASSET})"

# ─── Step 5: 下载 cloudflared (Argo) ────────────────────────────────────────
step "下载 cloudflared (Argo 隧道)"

ARGO_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/${ARGO_ASSET}"
ARGO_OUT="${WORK_DIR}/argo_raw"

download_with_progress "$ARGO_URL" "$ARGO_OUT" "cloudflared (${ARGO_ASSET})"

# ─── Step 6: 解压 & 权限 ────────────────────────────────────────────────────
step "解压并配置二进制文件"

# 解压 xray
info "解压 Xray-core..."
unzip -o "${XRAY_ZIP}" -d "${WORK_DIR}/" > /dev/null 2>&1
rm -f "${XRAY_ZIP}"
# 清理 zip 内附带的数据文件（节省空间）
rm -f "${WORK_DIR}/geosite.dat" "${WORK_DIR}/geoip.dat" \
      "${WORK_DIR}/README.md" "${WORK_DIR}/LICENSE"

if [[ ! -f "${WORK_DIR}/xray" ]]; then
    fail "Xray 解压失败，未找到 ${WORK_DIR}/xray"
fi
chmod +x "${WORK_DIR}/xray"
info "xray 版本: $("${WORK_DIR}/xray" version 2>/dev/null | head -1 || echo '未知')"

# 处理 cloudflared
if [[ "${ARGO_ASSET}" == *.tgz ]] || [[ "${ARGO_ASSET}" == *.tar.gz ]]; then
    info "解压 cloudflared..."
    tar -xzf "${ARGO_OUT}" -C "${WORK_DIR}/" > /dev/null 2>&1
    rm -f "${ARGO_OUT}"
    # darwin tar 解压出的二进制名
    if [[ -f "${WORK_DIR}/cloudflared" ]]; then
        mv -f "${WORK_DIR}/cloudflared" "${WORK_DIR}/argo"
    fi
else
    mv -f "${ARGO_OUT}" "${WORK_DIR}/argo"
fi

if [[ ! -f "${WORK_DIR}/argo" ]]; then
    fail "cloudflared 处理失败，未找到 ${WORK_DIR}/argo"
fi
chmod +x "${WORK_DIR}/argo"
info "argo 版本: $("${WORK_DIR}/argo" version 2>/dev/null | head -1 || echo '未知')"

ok "二进制文件就绪"

# ─── Step 7: 生成密钥 & 配置文件 ────────────────────────────────────────────
step "生成密钥和节点配置"

UUID="${UUID:-$(gen_uuid)}"
BASE_PORT="${PORT:-$(random_port)}"
GRPC_PORT=$((BASE_PORT))
XHTTP_PORT=$((BASE_PORT + 1))

info "UUID      : ${UUID}"
info "gRPC port : ${GRPC_PORT}"
info "xHTTP port: ${XHTTP_PORT}"
info "Argo port : ${ARGO_PORT}"

# 生成 x25519 密钥对
info "生成 Reality x25519 密钥对..."
X25519_OUT=$("${WORK_DIR}/xray" x25519 2>/dev/null)
PRIVATE_KEY=$(echo "${X25519_OUT}" | grep -i 'private' | awk '{print $NF}')
PUBLIC_KEY=$(echo "${X25519_OUT}"  | grep -i 'public'  | awk '{print $NF}')

if [[ -z "${PRIVATE_KEY}" ]] || [[ -z "${PUBLIC_KEY}" ]]; then
    fail "x25519 密钥生成失败，请检查 xray 二进制是否正常"
fi
info "私钥 (私有): ${PRIVATE_KEY:0:8}...${PRIVATE_KEY: -4}"
info "公钥 (节点): ${PUBLIC_KEY:0:8}...${PUBLIC_KEY: -4}"

# 写配置文件
cat > "${CONFIG_FILE}" << EOF
{
  "log": { "access": "/dev/null", "error": "/dev/null", "loglevel": "none" },
  "inbounds": [
    {
      "port": ${ARGO_PORT},
      "protocol": "vless",
      "settings": {
        "clients": [{ "id": "${UUID}" }],
        "decryption": "none",
        "fallbacks": [
          { "dest": 3001 },
          { "path": "/vless-argo", "dest": 3002 },
          { "path": "/vmess-argo", "dest": 3003 }
        ]
      },
      "streamSettings": { "network": "tcp" }
    },
    {
      "port": 3001, "listen": "127.0.0.1", "protocol": "vless",
      "settings": { "clients": [{ "id": "${UUID}" }], "decryption": "none" },
      "streamSettings": { "network": "tcp", "security": "none" }
    },
    {
      "port": 3002, "listen": "127.0.0.1", "protocol": "vless",
      "settings": { "clients": [{ "id": "${UUID}", "level": 0 }], "decryption": "none" },
      "streamSettings": {
        "network": "ws", "security": "none",
        "wsSettings": { "path": "/vless-argo" }
      },
      "sniffing": { "enabled": true, "destOverride": ["http","tls","quic"] }
    },
    {
      "port": 3003, "listen": "127.0.0.1", "protocol": "vmess",
      "settings": { "clients": [{ "id": "${UUID}", "alterId": 0 }] },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "/vmess-argo" }
      },
      "sniffing": { "enabled": true, "destOverride": ["http","tls","quic"] }
    },
    {
      "listen": "::", "port": ${XHTTP_PORT}, "protocol": "vless",
      "settings": { "clients": [{ "id": "${UUID}" }], "decryption": "none" },
      "streamSettings": {
        "network": "xhttp",
        "security": "reality",
        "realitySettings": {
          "target": "www.nazhumi.com:443",
          "xver": 0,
          "serverNames": ["www.nazhumi.com"],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": [""]
        }
      },
      "sniffing": { "enabled": true, "destOverride": ["http","tls","quic"] }
    },
    {
      "listen": "::", "port": ${GRPC_PORT}, "protocol": "vless",
      "settings": { "clients": [{ "id": "${UUID}" }], "decryption": "none" },
      "streamSettings": {
        "network": "grpc",
        "security": "reality",
        "realitySettings": {
          "dest": "www.iij.ad.jp:443",
          "serverNames": ["www.iij.ad.jp"],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": [""]
        },
        "grpcSettings": { "serviceName": "grpc" }
      },
      "sniffing": { "enabled": true, "destOverride": ["http","tls","quic"] }
    }
  ],
  "dns": { "servers": ["https+local://8.8.8.8/dns-query"] },
  "outbounds": [
    { "protocol": "freedom", "tag": "direct" },
    { "protocol": "blackhole", "tag": "block" }
  ]
}
EOF

ok "配置文件生成完成: ${CONFIG_FILE}"

# ─── Step 8: 启动 Xray ───────────────────────────────────────────────────────
step "启动 Xray 服务"

if $IS_MACOS; then
    # macOS: 后台运行
    # 不用 nohup —— 当脚本通过 bash <(curl -Ls ...) 运行时 stdin 是 pipe 而非 tty，
    # nohup 会报 "can't detach from console: Inappropriate ioctl for device"
    # 改为显式将 stdin 重定向到 /dev/null，用 disown 脱离 shell 作业表
    "${WORK_DIR}/xray" run -c "${CONFIG_FILE}" \
        < /dev/null \
        > "${XRAY_LOG}" 2>&1 &
    XRAY_PID=$!
    disown "$XRAY_PID" 2>/dev/null || true
    info "Xray PID: ${XRAY_PID}"
    sleep 2

    if kill -0 "$XRAY_PID" 2>/dev/null; then
        ok "Xray 已在后台启动 (PID: ${XRAY_PID})"
        info "日志: ${XRAY_LOG}"
        info "快捷停止: pkill -f '${WORK_DIR}/xray run'"
    else
        r "Xray 启动失败，日志如下:"
        tail -20 "${XRAY_LOG}" 2>/dev/null || true
        fail "Xray 进程已退出，请检查配置"
    fi
else
    # Linux: systemd
    cat > /etc/systemd/system/xray.service << SVCEOF
[Unit]
Description=Xray Service
Documentation=https://github.com/XTLS/Xray-core
After=network.target nss-lookup.target

[Service]
Type=simple
NoNewPrivileges=yes
ExecStart=${WORK_DIR}/xray run -c ${CONFIG_FILE}
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
SVCEOF

    systemctl daemon-reload
    systemctl enable xray --now
    sleep 2

    if systemctl is-active --quiet xray; then
        ok "Xray systemd 服务已启动"
        info "查看状态: systemctl status xray"
        info "查看日志: journalctl -u xray -f"
    else
        r "Xray 服务启动失败:"
        systemctl status xray --no-pager | tail -20
        fail "请检查配置文件: ${CONFIG_FILE}"
    fi

    # 关闭防火墙 (Linux)
    iptables -F >/dev/null 2>&1 && \
    iptables -P INPUT ACCEPT >/dev/null 2>&1 && \
    iptables -P FORWARD ACCEPT >/dev/null 2>&1 && \
    iptables -P OUTPUT ACCEPT >/dev/null 2>&1 || true
    command -v ip6tables &>/dev/null && \
        ip6tables -F >/dev/null 2>&1 && \
        ip6tables -P INPUT ACCEPT >/dev/null 2>&1 || true
    info "已配置 iptables 放行规则"
fi

# ─── Step 9: 启动 Argo 并等待临时域名 ───────────────────────────────────────
step "启动 Argo 临时隧道 & 获取域名"

rm -f "${ARGO_LOG}"

# 启动 argo（同样避免 nohup，原因同 xray 启动部分）
"${WORK_DIR}/argo" tunnel \
    --url "http://localhost:${ARGO_PORT}" \
    --no-autoupdate \
    --edge-ip-version auto \
    --protocol http2 \
    < /dev/null \
    > "${ARGO_LOG}" 2>&1 &

ARGO_PID=$!
disown "$ARGO_PID" 2>/dev/null || true
info "Argo PID: ${ARGO_PID}"
info "正在等待 trycloudflare.com 临时域名分配..."

# 等待域名出现（最多 40 秒）
ARGO_DOMAIN=""
for i in $(seq 1 20); do
    sleep 2
    ARGO_DOMAIN=$(sed -n 's|.*https://\([^/]*trycloudflare\.com\).*|\1|p' "${ARGO_LOG}" 2>/dev/null | tail -1)
    if [[ -n "${ARGO_DOMAIN}" ]]; then
        break
    fi
    printf "\r  ${CYAN}│  等待域名... %ds${RESET}" $((i*2))
done
echo ""

if [[ -z "${ARGO_DOMAIN}" ]]; then
    warn "未能在 40 秒内获取 Argo 临时域名"
    warn "可能原因: 网络不通 Cloudflare 或已达速率限制"
    warn "请稍后查看: ${ARGO_LOG}"
    ARGO_DOMAIN="<argo-domain-pending>"
else
    ok "Argo 临时域名: ${ARGO_DOMAIN}"
fi

if $IS_MACOS; then
    if kill -0 "$ARGO_PID" 2>/dev/null; then
        ok "Argo 运行正常 (PID: ${ARGO_PID})"
        info "快捷停止: pkill -f '${WORK_DIR}/argo tunnel'"
    else
        warn "Argo 进程已退出，日志:"
        tail -20 "${ARGO_LOG}"
    fi
else
    # Linux: 也配置 systemd tunnel 服务
    cat > /etc/systemd/system/tunnel.service << TEOF
[Unit]
Description=Cloudflare Tunnel
After=network.target

[Service]
Type=simple
NoNewPrivileges=yes
TimeoutStartSec=0
ExecStart=${WORK_DIR}/argo tunnel --url http://localhost:${ARGO_PORT} --no-autoupdate --edge-ip-version auto --protocol http2
StandardOutput=append:${ARGO_LOG}
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
TEOF
    # 把我们已启动的进程接管用 systemd
    kill "$ARGO_PID" 2>/dev/null || true
    systemctl daemon-reload
    systemctl enable tunnel --now
    info "Argo 已通过 systemd 托管: systemctl status tunnel"
fi

# ─── Step 10: 获取公网 IP & 生成节点链接 ─────────────────────────────────────
step "生成节点订阅信息"

CFIP="${CFIP:-icook.tw}"
CFPORT="${CFPORT:-443}"

info "获取公网 IP..."
PUBLIC_IP=$(curl -s --max-time 5 ipv4.ip.sb 2>/dev/null || true)
if [[ -z "${PUBLIC_IP}" ]]; then
    IPV6=$(curl -s --max-time 5 ipv6.ip.sb 2>/dev/null || true)
    PUBLIC_IP="[${IPV6}]"
fi
info "公网 IP: ${PUBLIC_IP}"

ISP=$(curl -sm 4 -H "User-Agent: Mozilla" "https://api.ip.sb/geoip" 2>/dev/null | \
    awk -F'"' '{for(i=1;i<=NF;i++){if($i=="country_code")cc=$(i+2);if($i=="isp")isp=$(i+2)};if(cc&&isp)print cc"-"isp}' | \
    sed 's/ /_/g' || echo "vps")

info "ISP: ${ISP}"

# 生成节点链接
VLESS_REALITY_GRPC="vless://${UUID}@${PUBLIC_IP}:${GRPC_PORT}?encryption=none&security=reality&sni=www.iij.ad.jp&fp=chrome&pbk=${PUBLIC_KEY}&allowInsecure=1&type=grpc&authority=www.iij.ad.jp&serviceName=grpc&mode=gun#${ISP}-gRPC"

VLESS_REALITY_XHTTP="vless://${UUID}@${PUBLIC_IP}:${XHTTP_PORT}?encryption=none&security=reality&sni=www.nazhumi.com&fp=chrome&pbk=${PUBLIC_KEY}&allowInsecure=1&type=xhttp&mode=auto#${ISP}-xHTTP"

VLESS_ARGO_WS="vless://${UUID}@${CFIP}:${CFPORT}?encryption=none&security=tls&sni=${ARGO_DOMAIN}&fp=chrome&type=ws&host=${ARGO_DOMAIN}&path=%2Fvless-argo%3Fed%3D2560#${ISP}-Argo-WS"

VMESS_ARGO_WS="vmess://$(echo "{\"v\":\"2\",\"ps\":\"${ISP}-Argo-VMess\",\"add\":\"${CFIP}\",\"port\":\"${CFPORT}\",\"id\":\"${UUID}\",\"aid\":\"0\",\"scy\":\"none\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"${ARGO_DOMAIN}\",\"path\":\"/vmess-argo?ed=2560\",\"tls\":\"tls\",\"sni\":\"${ARGO_DOMAIN}\",\"alpn\":\"\",\"fp\":\"chrome\"}" | base64_nowrap)"

# 写入文件
cat > "${URL_FILE}" << URLEOF
${VLESS_REALITY_GRPC}

${VLESS_REALITY_XHTTP}

${VLESS_ARGO_WS}

${VMESS_ARGO_WS}
URLEOF

# 生成 base64 订阅（Linux）
if ! $IS_MACOS; then
    base64_nowrap "${URL_FILE}" > "${SUB_FILE}"
fi

ok "节点信息已写入: ${URL_FILE}"

# ─── 创建快捷管理脚本 ────────────────────────────────────────────────────────
cat > "${WORK_DIR}/manage.sh" << 'MANAGE'
#!/usr/bin/env bash
# Xray-2go 简易管理

WORK_DIR="$(cd "$(dirname "$0")" && pwd)"
IS_MACOS=false
[[ "$(uname -s)" == "Darwin" ]] && IS_MACOS=true

case "${1:-status}" in
    start)
        if $IS_MACOS; then
            "$WORK_DIR/xray" run -c "$WORK_DIR/config.json" \
                < /dev/null > "$WORK_DIR/xray.log" 2>&1 &
            disown $! 2>/dev/null || true
            echo "Xray started (PID $!)"
            "$WORK_DIR/argo" tunnel --url "http://localhost:8080" --no-autoupdate --edge-ip-version auto --protocol http2 \
                < /dev/null > "$WORK_DIR/argo.log" 2>&1 &
            disown $! 2>/dev/null || true
            echo "Argo started (PID $!)"
        else
            systemctl start xray tunnel
        fi ;;
    stop)
        if $IS_MACOS; then
            pkill -f "$WORK_DIR/xray run" && echo "Xray stopped" || echo "Xray not running"
            pkill -f "$WORK_DIR/argo tunnel" && echo "Argo stopped" || echo "Argo not running"
        else
            systemctl stop xray tunnel
        fi ;;
    restart)
        "$0" stop; sleep 1; "$0" start ;;
    status)
        if $IS_MACOS; then
            pgrep -f "$WORK_DIR/xray run" > /dev/null && echo "Xray: running" || echo "Xray: stopped"
            pgrep -f "$WORK_DIR/argo tunnel" > /dev/null && echo "Argo: running" || echo "Argo: stopped"
        else
            systemctl status xray --no-pager -l
            systemctl status tunnel --no-pager -l
        fi ;;
    nodes)
        cat "$WORK_DIR/url.txt" ;;
    log-xray)
        if $IS_MACOS; then tail -50 "$WORK_DIR/xray.log"; else journalctl -u xray -n 50; fi ;;
    log-argo)
        tail -50 "$WORK_DIR/argo.log" ;;
    *)
        echo "用法: $0 {start|stop|restart|status|nodes|log-xray|log-argo}" ;;
esac
MANAGE
chmod +x "${WORK_DIR}/manage.sh"

# 创建全局快捷命令
ln -sf "${WORK_DIR}/manage.sh" "${BIN_PATH}" 2>/dev/null || true
[[ -L "${BIN_PATH}" ]] && ok "快捷命令已创建: 2go {start|stop|restart|status|nodes|log-xray|log-argo}"

# ─── 输出最终摘要 ─────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${CYAN}║${RESET}${BOLD}                    ✅ 安装完成！                             ${RESET}${CYAN}║${RESET}"
echo -e "${CYAN}╠══════════════════════════════════════════════════════════════╣${RESET}"
echo -e "${CYAN}║${RESET}  Xray   : ${GREEN}running${RESET}"
[[ "${ARGO_DOMAIN}" != "<argo-domain-pending>" ]] && \
echo -e "${CYAN}║${RESET}  Argo   : ${GREEN}${ARGO_DOMAIN}${RESET}" || \
echo -e "${CYAN}║${RESET}  Argo   : ${YELLOW}等待域名 (查看 ${ARGO_LOG})${RESET}"
echo -e "${CYAN}║${RESET}  配置   : ${CYAN}${CONFIG_FILE}${RESET}"
echo -e "${CYAN}║${RESET}  节点   : ${CYAN}${URL_FILE}${RESET}"
echo -e "${CYAN}╠══════════════════════════════════════════════════════════════╣${RESET}"
echo -e "${CYAN}║${RESET}${BOLD}  节点链接                                                    ${RESET}${CYAN}║${RESET}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${RESET}"
echo ""

echo -e "${YELLOW}── Reality gRPC ──────────────────────────────────────────────${RESET}"
echo -e "${PURPLE}${VLESS_REALITY_GRPC}${RESET}"
echo ""
echo -e "${YELLOW}── Reality xHTTP ─────────────────────────────────────────────${RESET}"
echo -e "${PURPLE}${VLESS_REALITY_XHTTP}${RESET}"
echo ""
echo -e "${YELLOW}── Argo VLESS-WS (CDN 优选 IP) ───────────────────────────────${RESET}"
echo -e "${PURPLE}${VLESS_ARGO_WS}${RESET}"
echo ""
echo -e "${YELLOW}── Argo VMess-WS (CDN 优选 IP) ───────────────────────────────${RESET}"
echo -e "${PURPLE}${VMESS_ARGO_WS}${RESET}"
echo ""

echo -e "${CYAN}─── 管理命令 ──────────────────────────────────────────────────${RESET}"
echo -e "  ${GREEN}2go status${RESET}    查看运行状态"
echo -e "  ${GREEN}2go nodes${RESET}     查看节点链接"
echo -e "  ${GREEN}2go restart${RESET}   重启服务"
echo -e "  ${GREEN}2go log-argo${RESET}  查看 Argo 日志（含域名）"
echo ""

if $IS_MACOS; then
    echo -e "${YELLOW}⚠  macOS 提示: 重启后服务不会自动启动，需手动执行 2go start${RESET}"
    echo -e "${YELLOW}   如需开机自启，可将以下内容加入 /etc/rc.local 或配置 launchd${RESET}"
    echo ""
fi
