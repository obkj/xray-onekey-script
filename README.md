支持 **macOS** 和 **Linux**，一键生成 VMess-Argo-WS 隧道节点，支持自定义 CF 优选 IP。

- **极简安装**：支持 **macOS** 和 **Linux**，一键生成 VMess-Argo-WS 隧道节点。
- **自动检测提权**：检测到非 root 权限时自动尝试使用 `sudo` 重新运行。
- **高可用重试**：安装过程中自动探测 Argo 域名状态，若遇 530/1033 错误自动重启重试（最多 5 次）。
- **智能管理**：提供 `2go` 快捷管理脚本，集成启动、停止、重启、查看日志与节点等功能。
- **配置优化**：所有监听端口均采用 50000 以上的随机端口，增强安全性。

---

| 节点 | 协议 | 传输 | 穿透 | 说明 |
|------|------|------|------|------|
| Argo VMess-WS | VMess | WebSocket | Cloudflare Tunnel | 默认直连域名，可选优选 IP |
| Native Reverse | VMess | WebSocket | CF Origin Rules | 专为套 CF 设计的双路径穿透方案 |

---

## 快速安装

### `install_argo.sh` — 无交互版（推荐）

支持 **macOS** 和 **Linux**，自动完成所有步骤，无需人工输入。

```bash
curl -Lo install_argo.sh "https://raw.githubusercontent.com/obkj/xray-onekey-script/main/install_argo.sh?t=$(date +%s)" && chmod +x install_argo.sh && ./install_argo.sh
```

安装完成后自动输出所有节点链接，并创建快捷管理命令 `2go`。

### `install_xray_reverse.sh` — 原生反代版 (VMess + WS + CF)

专为套 Cloudflare 设计。支持 **Portal (服务端)** 与 **Bridge (客户端)** 角色切换，支持双路径回源与 VMess 加密。

```bash
curl -Lo install_xray_reverse.sh "https://raw.githubusercontent.com/obkj/xray-onekey-script/main/install_xray_reverse.sh?t=$(date +%s)" && chmod +x install_xray_reverse.sh && ./install_xray_reverse.sh
```

**示例配置：** [服务端 (server.json)](./server.json) | [客户端 (client.json)](./client.json)

### `install.sh` — 交互版（Linux）

仅支持 **Linux（Debian / Ubuntu / CentOS / Alpine）**，包含完整菜单管理界面。

```bash
bash <(curl -Ls https://raw.githubusercontent.com/obkj/xray-onekey-script/main/install.sh)
```

---

| 功能 | macOS | Linux |
|------|:-----:|:-----:|
| Xray 安装 | ✅ | ✅ |
| Argo 临时隧道 | ✅ | ✅ |
| Argo 固定隧道 | ❌ | ✅ |
| Caddy 订阅服务 | ❌ | ✅ |
| systemd 自启动 | ❌ | ✅ |
| 开机自动启动 | 需手动配置 launchd | ✅ 自动 |

---

## 安装后管理

安装完成后可使用 `2go` 命令进行管理：

```bash
2go status     # 查看 Xray / Argo 运行状态
2go nodes      # 显示所有节点链接
2go start      # 启动服务
2go stop       # 停止服务
2go restart    # 重启服务
2go log-xray   # 查看 Xray 日志
2go log-argo   # 查看 Argo 日志
2go uninstall  # 一键卸载
```

---

## 自定义环境变量

运行前可通过环境变量覆盖默认值：

```bash
# 示例：指定 UUID 和端口
UUID=your-uuid PORT=12345 curl -Lo install_argo.sh "https://raw.githubusercontent.com/obkj/xray-onekey-script/main/install_argo.sh?t=$(date +%s)" && chmod +x install_argo.sh && ./install_argo.sh

# 示例：自定义 CDN 优选 IP
CFIP=1.2.3.4 CFPORT=443 curl -Lo install_argo.sh "https://raw.githubusercontent.com/obkj/xray-onekey-script/main/install_argo.sh?t=$(date +%s)" && chmod +x install_argo.sh && ./install_argo.sh
```

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `UUID` | 随机生成 | 节点 UUID |
| `PORT` | 随机 50000–65535 | Xray 内部监听端口 |
| `CFIP` | (空) | 若为空则直连 Argo 域名；若指定则使用该优选 IP |
| `CFPORT` | `443` | 配合 `CFIP` 使用的端口 |

---

## 文件位置

| 路径 | 说明 |
|------|------|
| `/usr/local/etc/xray-argo/` (macOS) | 安装目录 |
| `/etc/xray-argo/` (Linux) | 安装目录 |
| `…/config.json` | Xray 配置文件 |
| `…/url.txt` | 节点链接文本 |
| `…/argo.log` | Argo 日志（含临时域名） |
| `…/xray.log` | Xray 运行日志 |
