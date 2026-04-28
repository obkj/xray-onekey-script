# Xray-2go 一键内网穿透脚本 (VMess + WS + CF 专用版)

利用 Xray 原生 `reverse` 模块实现的专业内网穿透方案。专为 Cloudflare CDN 环境优化，支持通过单端口双路径或独立 VMess 端口进行流量分发。

## 🌟 核心特性

- **可视化菜单**：集成安装、管理、映射、卸载于一体。
- **单端口多路径**：只需一个回源端口，通过 `/user` 和 `/tunnel` 路径区分用户流量与隧道流量。
- **多客户端支持**：服务端可动态添加多个内网客户端映射，支持路径隔离或端口隔离。
- **双工作模式**：
  - **转发模式**：将公网流量转发至内网 Web/数据库等服务。
  - **出口模式**：将内网客户端作为上网出口，实现通过穿透隧道访问互联网（YouTube 等）。
- **二次加密**：强制使用 VMess (aes-128-gcm) + WebSocket + TLS，在 CDN 环境下保护数据隐私。

---

## 🚀 快速安装

```bash
curl -Lo install_xray_reverse.sh "https://raw.githubusercontent.com/obkj/xray-onekey-script/main/install_xray_reverse.sh?t=$(date +%s)" && chmod +x install_xray_reverse.sh && ./install_xray_reverse.sh
```

---

## 🛠️ 功能说明

### 1. 安装服务端 (Portal)
运行在具有公网 IP 的 VPS 上。建议开启 Cloudflare Proxy。
- **监听端口**：服务端接收流量的端口（建议使用随机高位端口）。
- **路径分流**：根据 URL Path 将请求分发给对应的反代标签。

### 2. 添加新客户端配置 (仅服务端)
当您需要穿透多个内网设备时，在服务端运行此选项。
- 为每个设备分配唯一的**识别域名**（如 `pc1.local`）和**访问路径**（如 `/pc1`）。

### 3. 管理 VMess 端口映射 (仅服务端)
除了通过域名路径访问，还可以为特定内网设备开启独立的公网端口。
- **端口映射**：`VPS:20000` -> `内网设备 A`。
- 适合远程桌面、SSH 等非 Web 业务。

### 4. 安装客户端 (Bridge)
运行在内网主机上。
- **转发模式**：填写内网服务的监听地址（如 `127.0.0.1:80`）。
- **出口模式**：无需填写目标，该客户端将直接作为上网代理出口。

---

## 📖 部署示例 (套 CF)

1. **服务端**：安装 Portal，设置监听端口为 `54321`，路径为 `/user`。
2. **Cloudflare**：
   - 解析域名到 VPS IP。
   - 在 **Origin Rules** 中设置：如果路径包含 `/user` 或 `/tunnel`，则回源端口改为 `54321`。
3. **客户端**：安装 Bridge，模式选择“出口模式”。
4. **使用**：在服务端添加一个映射端口 `10086`。本地连接 `VPS:10086` 即可通过内网主机的网络上网。
5. **参考配置**：[服务端 (server.json)](./examples/server.json) | [客户端 (client.json)](./examples/client.json)

---

## 🗂️ 目录与管理

- **安装目录**：`/etc/xray-rev` (Root) 或 `~/.local/share/xray-rev` (非 Root)。
- **服务管理**：
  ```bash
  systemctl --user status xray-rev    # 查看状态
  systemctl --user restart xray-rev   # 重启服务
  ```

---

## 📄 许可说明
本项目基于 Xray-core。请在遵守当地法律法规的前提下使用。
