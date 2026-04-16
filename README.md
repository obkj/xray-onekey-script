支持 **macOS** 和 **Linux**，生成 VMess-Argo-WS 隧道节点。采用 **Direct First** 策略，默认直连 Argo 域名，支持自定义 CF 优选 IP。

---

| 节点 | 协议 | 传输 | 穿透 | 说明 |
|------|------|------|------|------|
| Argo VMess-WS | VMess | WebSocket | Cloudflare Tunnel | 默认直连域名，可选优选 IP |

---

## 快速安装

### `install_argo.sh` — 无交互版（推荐）

支持 **macOS** 和 **Linux**，自动完成所有步骤，无需人工输入。

```bash
bash <(curl -Ls https://raw.githubusercontent.com/obkj/xray-onekey-script/main/install_argo.sh)
```

安装完成后自动输出所有节点链接，并创建快捷管理命令 `2go`。

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
2go log-argo   # 查看 Argo 日志（含临时域名）
```

---

## 自定义环境变量

运行前可通过环境变量覆盖默认值：

```bash
# 示例：指定 UUID 和端口
UUID=your-uuid PORT=12345 bash <(curl -Ls .../install_argo.sh)

# 示例：自定义 CDN 优选 IP
CFIP=1.2.3.4 CFPORT=443 bash <(curl -Ls .../install_argo.sh)
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
| `/usr/local/etc/xray/` (macOS) | 安装目录 |
| `/etc/xray/` (Linux) | 安装目录 |
| `…/config.json` | Xray 配置文件 |
| `…/url.txt` | 节点链接文本 |
| `…/argo.log` | Argo 日志（含临时域名） |
| `…/xray.log` | Xray 运行日志 |
