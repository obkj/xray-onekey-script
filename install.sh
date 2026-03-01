#!/bin/bash

# Xray Reality One-Key Installer
# Adapted for Xray-core with VLESS-XTLS-uTLS-REALITY

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"

XRAY_CONFIG_FILE="/usr/local/etc/xray/config.json"
XRAY_PUBLIC_KEY_FILE="/usr/local/etc/xray/public.key"
XRAY_BIN_PATH="/usr/local/bin/xray"
SYSTEMD_FILE="/etc/systemd/system/xray.service"

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: This script must be run as root!${PLAIN}"
        exit 1
    fi
}

install_dependencies() {
    echo -e "${YELLOW}Installing dependencies...${PLAIN}"
    if [[ -f /etc/debian_version ]]; then
        apt-get update
        apt-get install -y curl wget tar unzip jq openssl uuid-runtime net-tools qrencode procps gawk
    elif [[ -f /etc/redhat-release ]]; then
        yum install -y curl wget tar unzip jq openssl net-tools qrencode procps
    elif [[ -f /etc/openwrt_release ]] || [[ -f /etc/opkg.conf ]]; then
        opkg update
        opkg install bash curl wget-ssl unzip jq openssl-util uuidgen ca-bundle net-tools-netstat qrencode
    elif [[ -f /etc/alpine-release ]]; then
        apk update
        apk add bash curl wget tar unzip jq openssl util-linux net-tools qrencode ca-certificates
    else
        echo -e "${RED}Unsupported OS${PLAIN}"
        exit 1
    fi
}

install_xray_core() {
    echo -e "${YELLOW}Downloading Xray-core...${PLAIN}"
    # Get latest release version
    LATEST_VER=$(curl -s https://api.github.com/repos/obkj/xray-reality-shell/releases/latest | jq -r .tag_name)
    if [[ -z "$LATEST_VER" ]]; then
        echo -e "${RED}Failed to fetch latest Xray version.${PLAIN}"
        exit 1
    fi
    
    echo -e "${GREEN}Latest version: ${LATEST_VER}${PLAIN}"
    
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH="64" ;;
        aarch64) ARCH="arm64-v8a" ;;
        *) echo -e "${RED}Unsupported architecture: $ARCH${PLAIN}"; exit 1 ;;
    esac

    DOWNLOAD_URL="https://github.com/obkj/xray-reality-shell/releases/download/${LATEST_VER}/Xray-linux-${ARCH}.zip"
    
    mkdir -p /tmp/xray
    wget -O /tmp/xray/xray.zip "$DOWNLOAD_URL"
    
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}Download failed.${PLAIN}"
        exit 1
    fi

    unzip -o /tmp/xray/xray.zip -d /tmp/xray
    mv /tmp/xray/xray "$XRAY_BIN_PATH"
    chmod +x "$XRAY_BIN_PATH"
    rm -rf /tmp/xray
    
    mkdir -p /usr/local/etc/xray
    mkdir -p /var/log/xray
}

generate_config() {
    echo -e "${YELLOW}Generating configuration...${PLAIN}"
    
    # Generate UUID
    if command -v uuidgen >/dev/null; then
        UUID=$(uuidgen)
    else
        UUID=$(cat /proc/sys/kernel/random/uuid)
    fi
    
    # Generate Keys
    KEYS=$($XRAY_BIN_PATH x25519)
    PRIVATE_KEY=$(echo "$KEYS" | grep -i "Private" | awk '{print $NF}')
    PUBLIC_KEY=$(echo "$KEYS" | grep -i "Password" | awk '{print $NF}')
    
    if [[ -z "$PRIVATE_KEY" ]] || [[ -z "$PUBLIC_KEY" ]]; then
        echo -e "${RED}Error: Failed to generate Xray keys.${PLAIN}"
        echo -e "${RED}Debug: $KEYS${PLAIN}"
        exit 1
    fi
    
    # Save Public Key for later retrieval
    echo "$PUBLIC_KEY" > "$XRAY_PUBLIC_KEY_FILE"
    
    # Generate ShortId
    SHORT_ID=$(openssl rand -hex 8)
    
    # Generate Random High Port (50000+)
    echo -e "${YELLOW}Generating random high port (50000+)...${PLAIN}"
    while true; do
        PORT=$((RANDOM % 15536 + 50000))
        if command -v netstat >/dev/null; then
            if netstat -tuln | grep -q ":$PORT "; then
                continue
            fi
        elif command -v ss >/dev/null; then
            if ss -tuln | grep -q ":$PORT "; then
                continue
            fi
        fi
        echo -e "Using Port: ${GREEN}${PORT}${PLAIN}"
        break
    done
    
    read -p "Enter SNI/Dest (default www.microsoft.com): " DEST
    [[ -z "$DEST" ]] && DEST="www.microsoft.com"

    cat > "$XRAY_CONFIG_FILE" <<EOF
{
  "log": {
    "loglevel": "error",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "inbounds": [
    {
      "port": $PORT,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${DEST}:443",
          "serverNames": [
            "${DEST}"
          ],
          "privateKey": "$PRIVATE_KEY",
          "shortIds": [
            "$SHORT_ID"
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls",
          "quic"
        ]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ]
}
EOF
}

setup_service() {
    echo -e "${YELLOW}Setting up Service...${PLAIN}"
    
    if [[ -f /etc/openwrt_release ]]; then
        cat > "/etc/init.d/xray" <<EOF
#!/bin/sh /etc/rc.common
START=99
STOP=10
USE_PROCD=1

PROG=$XRAY_BIN_PATH
CONF=$XRAY_CONFIG_FILE

start_service() {
	procd_open_instance
	procd_set_param command "\$PROG" run -config "\$CONF"
	procd_set_param respawn
	procd_set_param stdout 1
	procd_set_param stderr 1
	procd_set_param user root
	procd_close_instance
}
EOF
        chmod +x /etc/init.d/xray
        /etc/init.d/xray enable
        /etc/init.d/xray restart
    elif [[ -f /etc/alpine-release ]]; then
        cat > "/etc/init.d/xray" <<EOF
#!/sbin/openrc-run

name="xray"
description="Xray Service"
command="$XRAY_BIN_PATH"
command_args="run -config $XRAY_CONFIG_FILE"
command_background=true
pidfile="/run/xray.pid"

depend() {
    need net
    use dns
}
EOF
        chmod +x /etc/init.d/xray
        rc-update add xray default
        service xray restart
    else
        cat > "$SYSTEMD_FILE" <<EOF
[Unit]
Description=Xray Service
Documentation=https://github.com/xtls
After=network.target nss-lookup.target

[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=$XRAY_BIN_PATH run -config $XRAY_CONFIG_FILE
Restart=on-failure
RestartPreventExitStatus=23

[Install]
WantedBy=multi-user.target
EOF

        systemctl daemon-reload
        systemctl enable xray
        systemctl restart xray
    fi
}

is_running() {
    if [[ -f /etc/systemd/system/xray.service ]]; then
        systemctl is-active xray >/dev/null 2>&1
        return $?
    else
        # OpenWrt / Alpine (check process)
        pgrep -f "xray run" >/dev/null 2>&1
        return $?
    fi
}

create_shortcut() {
    echo -e "${YELLOW}Creating shortcut 'xr'...${PLAIN}"
    wget -O /usr/local/bin/xr https://raw.githubusercontent.com/obkj/xray-reality-shell/main/install.sh
    chmod +x /usr/local/bin/xr
    echo -e "${GREEN}Shortcut 'xr' created. You can run this script by typing 'xr'.${PLAIN}"
}

restart_service() {
    echo -e "${YELLOW}Restarting Xray service...${PLAIN}"
    if [[ -f /etc/openwrt_release ]] || [[ -f /etc/alpine-release ]]; then
        /etc/init.d/xray restart
    else
        systemctl restart xray
    fi
}

show_info() {
    if [[ ! -f "$XRAY_CONFIG_FILE" ]]; then
        echo -e "${RED}Xray config not found!${PLAIN}"
        return
    fi

    if [[ -z "$UUID" ]] || [[ "$UUID" == "null" ]]; then
        UUID=$(jq -r '.inbounds[0].settings.clients[0].id' "$XRAY_CONFIG_FILE")
        PORT=$(jq -r '.inbounds[0].port' "$XRAY_CONFIG_FILE")
        DEST=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' "$XRAY_CONFIG_FILE")
        SHORT_ID=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' "$XRAY_CONFIG_FILE")
    fi

    if [[ -z "$PUBLIC_KEY" ]] || [[ "$PUBLIC_KEY" == "null" ]]; then
        if [[ -f "$XRAY_PUBLIC_KEY_FILE" ]]; then
            PUBLIC_KEY=$(cat "$XRAY_PUBLIC_KEY_FILE")
        else
            PUBLIC_KEY="unknown"
        fi
    fi

    # Get IP
    IP=$(curl -s4 -m 5 ifconfig.me || curl -s4 -m 5 api.ip.sb/ip)

    # Get ISP Info (Remark)
    REMARK=$(curl -sm 3 -H "User-Agent: Mozilla/5.0" "https://api.ip.sb/geoip" | tr -d '\n' | awk -F\" '{c="";i="";for(x=1;x<=NF;x++){if($x=="country_code")c=$(x+2);if($x=="isp")i=$(x+2)};if(c&&i)print c"-"i}' | sed 's/ /_/g' || curl -sm 3 -H "User-Agent: Mozilla/5.0" "https://ipapi.co/json" | tr -d '\n' | awk -F\" '{c="";o="";for(x=1;x<=NF;x++){if($x=="country_code")c=$(x+2);if($x=="org")o=$(x+2)};if(c&&o)print c"-"o}' | sed 's/ /_/g' || echo "VPS")

    SHARE_LINK="vless://${UUID}@${IP}:${PORT}?security=reality&encryption=none&pbk=${PUBLIC_KEY}&headerType=none&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni=${DEST}&sid=${SHORT_ID}&spx=%2F#${REMARK}"
    
    if command -v qrencode >/dev/null; then
        echo -e "${YELLOW}QR Code:${PLAIN}"
        qrencode -t ANSIUTF8 "${SHARE_LINK}"
        echo -e ""
    fi
    echo -e "----------------vless Share Link----------------"
    echo -e "${GREEN}${SHARE_LINK}${PLAIN}"
    echo -e "------------------------------------------------"

    # Save share link to file
    echo "${SHARE_LINK}" > /usr/local/etc/xray/share_link.txt
}

open_port() {
    local port=$1
    [[ -z "$port" ]] && return

    echo -e "${YELLOW}Opening port $port...${PLAIN}"

    if [[ -f /etc/openwrt_release ]]; then
        uci set firewall.xray=rule
        uci set firewall.xray.name='xray'
        uci set firewall.xray.src='wan'
        uci set firewall.xray.dest_port="$port"
        uci set firewall.xray.proto='tcp'
        uci set firewall.xray.target='ACCEPT'
        uci commit firewall
        /etc/init.d/firewall restart
    elif command -v ufw >/dev/null; then
        ufw allow "$port"/tcp
        ufw reload
    elif command -v firewall-cmd >/dev/null; then
        firewall-cmd --zone=public --add-port="$port"/tcp --permanent
        firewall-cmd --reload
    elif command -v iptables >/dev/null; then
        iptables -I INPUT -p tcp --dport "$port" -j ACCEPT
    fi
}

close_port() {
    local port=$1
    [[ -z "$port" ]] && return

    echo -e "${YELLOW}Closing port $port...${PLAIN}"

    if [[ -f /etc/openwrt_release ]]; then
        uci delete firewall.xray
        uci commit firewall
        /etc/init.d/firewall restart
    elif command -v ufw >/dev/null; then
        ufw delete allow "$port"/tcp
        ufw reload
    elif command -v firewall-cmd >/dev/null; then
        firewall-cmd --zone=public --remove-port="$port"/tcp --permanent
        firewall-cmd --reload
    elif command -v iptables >/dev/null; then
        iptables -D INPUT -p tcp --dport "$port" -j ACCEPT
    fi
}

install_full() {
    install_dependencies
    install_xray_core
    generate_config
    open_port $PORT
    setup_service
    create_shortcut
    
    if is_running; then
        show_info
    else
        echo -e "${RED}Xray failed to start! Please check logs.${PLAIN}"
        if [[ -f /etc/systemd/system/xray.service ]]; then
            journalctl -u xray --no-pager | tail -n 10
        fi
    fi
}

uninstall_xray() {
    echo -e "${YELLOW}Uninstalling Xray...${PLAIN}"
    if [[ -f "$XRAY_CONFIG_FILE" ]]; then
        PORT=$(jq -r '.inbounds[0].port' "$XRAY_CONFIG_FILE")
        close_port $PORT
    fi

    if [[ -f /etc/openwrt_release ]] || [[ -f /etc/alpine-release ]]; then
        /etc/init.d/xray stop
        if command -v rc-update >/dev/null; then
            rc-update del xray default
        else
            /etc/init.d/xray disable
        fi
        rm -f /etc/init.d/xray
    else
        systemctl stop xray
        systemctl disable xray
        rm -f "$SYSTEMD_FILE"
        systemctl daemon-reload
    fi
    
    rm -rf "$XRAY_BIN_PATH"
    rm -rf /usr/local/etc/xray
    rm -rf /var/log/xray
    rm -f /usr/local/bin/xr
    
    echo -e "${GREEN}Xray uninstalled.${PLAIN}"
}

change_port() {
    if [[ ! -f "$XRAY_CONFIG_FILE" ]]; then
        echo -e "${RED}Xray not installed.${PLAIN}"
        return
    fi
    
    read -p "Enter new Port (default random): " NEW_PORT
    if [[ -z "$NEW_PORT" ]]; then
        while true; do
            NEW_PORT=$((RANDOM % 15536 + 50000))
            if command -v netstat >/dev/null; then
                if netstat -tuln | grep -q ":$NEW_PORT "; then
                    continue
                fi
            elif command -v ss >/dev/null; then
                if ss -tuln | grep -q ":$NEW_PORT "; then
                    continue
                fi
            fi
            break
        done
    fi
    echo -e "Using Port: ${GREEN}${NEW_PORT}${PLAIN}"
    
    OLD_PORT=$(jq -r '.inbounds[0].port' "$XRAY_CONFIG_FILE")
    
    TMP_FILE=$(mktemp)
    jq --arg port "$NEW_PORT" '.inbounds[0].port = ($port|tonumber)' "$XRAY_CONFIG_FILE" > "$TMP_FILE" && mv "$TMP_FILE" "$XRAY_CONFIG_FILE"
    
    close_port $OLD_PORT
    open_port $NEW_PORT
    restart_service
    show_info
}

change_sni() {
    if [[ ! -f "$XRAY_CONFIG_FILE" ]]; then
        echo -e "${RED}Xray not installed.${PLAIN}"
        return
    fi

    read -p "Enter new SNI/Dest (e.g. www.google.com): " NEW_DEST
    [[ -z "$NEW_DEST" ]] && echo -e "${RED}SNI cannot be empty${PLAIN}" && return
    
    TMP_FILE=$(mktemp)
    jq --arg dest "$NEW_DEST" \
       '.inbounds[0].streamSettings.realitySettings.serverNames = [$dest] | .inbounds[0].streamSettings.realitySettings.dest = ($dest + ":443")' \
       "$XRAY_CONFIG_FILE" > "$TMP_FILE" && mv "$TMP_FILE" "$XRAY_CONFIG_FILE"
       
    restart_service
    show_info
}

toggle_bbr() {
    if [[ -f /etc/sysctl.conf ]]; then
        if grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf; then
            echo -e "${YELLOW}Disabling BBR...${PLAIN}"
            sed -i '/net.core.default_qdisc=fq/d' /etc/sysctl.conf
            sed -i '/net.ipv4.tcp_congestion_control=bbr/d' /etc/sysctl.conf
            sysctl -p
            echo -e "${GREEN}BBR disabled.${PLAIN}"
        else
            echo -e "${YELLOW}Enabling BBR...${PLAIN}"
            echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
            echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
            sysctl -p
            echo -e "${GREEN}BBR enabled.${PLAIN}"
        fi
    fi
}

menu() {
    clear
    echo -e "Xray Reality Management Script"
    echo -e "--------------------------------"
    if is_running; then
        echo -e "Status: ${GREEN}Running${PLAIN}"
    else
        echo -e "Status: ${RED}Stopped${PLAIN}"
    fi
    echo -e "--------------------------------"
    echo -e "1. Install Xray"
    echo -e "2. Uninstall Xray"
    echo -e "3. Change Port"
    echo -e "4. Change SNI"
    echo -e "5. Show Info"
    if grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf 2>/dev/null; then
        echo -e "6. Disable BBR"
    else
        echo -e "6. Enable BBR"
    fi
    echo -e "0. Exit"
    echo -e "--------------------------------"
    read -p "Choose an option: " choice
    
    case $choice in
        1) install_full ;;
        2) uninstall_xray ;;
        3) change_port ;;
        4) change_sni ;;
        5) show_info ;;
        6) toggle_bbr ;;
        0) exit 0 ;;
        *) echo -e "${RED}Invalid option${PLAIN}" ;;
    esac
}

main() {
    check_root
    menu
}

main