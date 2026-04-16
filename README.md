# xray-onekey-script

一键部署 Xray-core + Cloudflare Argo 临时隧道，无需交互，全程自动完成。

支持 **macOS** 和 **Linux**，生成 Reality gRPC、Reality xHTTP、Argo VMess-WS 三类节点。

---

## 节点类型

| 节点 | 协议 | 传输 | 穿透 | 说明 |
|------|------|------|------|------|
| Reality gRPC | VLESS | gRPC | 直连 | 抗封锁，需直连可用 |
| Reality xHTTP | VLESS | xHTTP | 直连 | 新型传输，需直连可用 |
| Argo VMess-WS | VMess | WebSocket | Cloudflare CDN | 兼容性最广，走优选 IP |

---

## 快速安装

### `install_argo.sh` — 无交互版（推荐）

支持 **macOS** 和 **Linux**，自动完成所有步骤，无需人工输入。

```bash
sudo bash <(curl -Ls https://raw.githubusercontent.com/obkj/xray-onekey-script/main/install_argo.sh)
```

安装完成后自动输出所有节点链接，并创建快捷管理命令 `2go`。

### `install.sh` — 交互版（Linux）

仅支持 **Linux（Debian / Ubuntu / CentOS / Alpine）**，包含完整菜单管理界面。

```bash
bash <(curl -Ls https://raw.githubusercontent.com/obkj/xray-onekey-script/main/install.sh)
```

---

## 平台支持

| 功能 | macOS | Linux |
|------|:-----:|:-----:|
| Xray 安装 | ✅ | ✅ |
| Reality 节点 | ✅ | ✅ |
| Argo 临时隧道 | ✅ | ✅ |
| Argo 固定隧道 | ❌ | ✅ |
| Caddy 订阅服务 | ❌ | ✅ |
| systemd 自启动 | ❌ | ✅ |
| 开机自动启动 | 需手动配置 launchd | ✅ 自动 |

---

## 安装后管理

安装完成后可使用 `2go` 命令进行管理：

```bash
2go status             # 查看 Xray / Argo 运行状态
2go nodes              # 显示所有节点链接
2go start              # 启动服务
2go stop               # 停止服务
2go restart            # 重启服务
2go log-xray           # 查看 Xray 日志
2go log-argo           # 查看 Argo 日志（含临时域名）
2go uninstall          # 卸载服务与安装目录（交互确认）
2go uninstall --force  # 强制卸载，不再二次确认
```

卸载时会停止 Xray / Argo，清理快捷命令 `2go`、相关服务文件，以及安装目录：

- macOS: `/usr/local/etc/xray`、`/usr/local/bin/2go`
- Linux: `/etc/xray`、`/usr/bin/2go`、`/etc/systemd/system/xray.service`、`/etc/systemd/system/tunnel.service`

---

## 自定义环境变量

运行前可通过环境变量覆盖默认值：

```bash
# 示例：指定 UUID 和基础端口（Reality gRPC 使用该端口，其他端口自动随机高位分配）
UUID=your-uuid PORT=12345 sudo bash <(curl -Ls .../install_argo.sh)

# 示例：自定义 CDN 优选 IP
CFIP=1.2.3.4 CFPORT=443 sudo bash <(curl -Ls .../install_argo.sh)
```

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `UUID` | 随机生成 | 节点 UUID |
| `PORT` | 随机 10000–60000 | Reality gRPC 端口；其余监听端口自动随机高位分配 |
| `CFIP` | `icook.tw` | Argo 节点使用的 CF 优选 IP / 域名 |
| `CFPORT` | `443` | Argo 节点端口 |

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
| `…/manage.sh` | `2go` 管理脚本 |
