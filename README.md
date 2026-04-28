# Xray Native Reverse Proxy (VMess + WS + CF)

利用 Xray 原生 `reverse` 模块实现的内网穿透方案，专为套 Cloudflare CDN 设计，提供极高的安全性和隐蔽性。

## 特性

- **原生反代**：使用 Xray native `reverse` 模块，无需额外穿透工具。
- **CF 深度适配**：支持通过 Cloudflare Origin Rules（回源规则）进行双路径分流。
- **双重加密**：VMess (128-bit) + WebSocket (TLS)，确保数据对 CDN 节点不透明。
- **正常代理出站**：内网客户端支持同时开启 SOCKS5 代理，实现正常上网。

---

## 快速安装

### `install_xray_reverse.sh`

支持 **Portal (服务端)** 与 **Bridge (客户端)** 角色切换。

```bash
curl -Lo install_xray_reverse.sh "https://raw.githubusercontent.com/obkj/xray-onekey-script/main/install_xray_reverse.sh?t=$(date +%s)" && chmod +x install_xray_reverse.sh && ./install_xray_reverse.sh
```

### 角色说明

1. **服务端 (Portal)**：运行在公网 VPS。配置 CF 回源规则，将不同路径转发到对应端口。
2. **客户端 (Bridge)**：运行在内网主机。通过 CF 域名连接服务端，并将流量转发至本地服务。

---

## 示例配置

- [服务端示例 (example_portal_cf.json)](./example_portal_cf.json)
- [客户端示例 (example_bridge_cf.json)](./example_bridge_cf.json)

---

## 管理维护

安装完成后可使用系统服务管理：

```bash
# Linux (systemd)
systemctl status xray-rev    # 查看状态
systemctl restart xray-rev   # 重启服务
```
