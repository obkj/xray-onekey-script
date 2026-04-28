# Xray-2go 一键安装脚本库

本仓库提供多种 Xray 安装方案，涵盖原生反代、Argo 隧道及常规部署，专为高速与安全设计。

---

## ⚡ 快速安装

根据您的需求选择对应的脚本：

### 1. 🚀 原生反代版 (推荐)
**特点**：专为套 CF 设计，支持单端口双路径、多客户端映射、出口模式。
```bash
curl -Ls https://raw.githubusercontent.com/obkj/xray-onekey-script/main/install_xray_reverse.sh -o install_xray_reverse.sh && bash install_xray_reverse.sh
```

### 2. ☁️ Argo 隧道版
**特点**：使用 Cloudflare Argo Tunnel 临时隧道，无需开放端口，适合内网无公网 IP 环境。
```bash
curl -Ls https://raw.githubusercontent.com/obkj/xray-onekey-script/main/install_argo.sh -o install_argo.sh && bash install_argo.sh
```

### 3. 🛠️ 常规交互版
**特点**：全功能菜单，支持多种协议（VLESS/VMess/Trojan）的常规部署。
```bash
curl -Ls https://raw.githubusercontent.com/obkj/xray-onekey-script/main/install.sh -o install.sh && bash install.sh
```

---

## 🌟 原生反代版功能详解 (Native Reverse)

### 核心优势
- **可视化菜单**：集成安装、多客户端管理、映射管理。
- **单端口多路径**：只需一个回源端口，通过路径区分流量。
- **出口模式**：可将内网客户端作为代理出口（访问 YouTube）。
- **直连/CF 双支持**：既可以套 CF 隐藏 IP，也可以直接通过 IP 高速连接。

### 功能清单
- **服务端 (Portal)**：安装后支持动态添加多个内网客户端。
- **端口映射**：支持 `VPS:Port` -> `内网设备` 的精准转发。
- **客户端 (Bridge)**：支持转发模式（Web）和出口模式（上网）。

---

## 📖 部署示例 (套 CF)

1. **服务端**：安装 Portal，设置监听端口为随机高位端口，路径为 `/user`。
2. **Cloudflare**：
   - 解析域名到 VPS IP。
   - 在 **Origin Rules** 中设置：如果路径包含 `/user` 或 `/tunnel`，则回源端口改为您的监听端口。
3. **客户端**：安装 Bridge，选择对应的识别域名。

---

## 📄 许可说明
本项目基于 Xray-core。请在遵守当地法律法规的前提下使用。
