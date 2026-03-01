# xray-reality-shell

A simple and efficient one-key deployment script for Xray with VLESS-XTLS-uTLS-REALITY architecture.

This script automates the installation of Xray-core, generates necessary keys, and configures the service for optimal performance and security.

## Features

- **Auto-Install**: Automatically downloads the latest Xray-core.
- **Reality Config**: Configures VLESS with XTLS-Vision and Reality security.
- **Key Generation**: Automatically generates UUID, Private/Public keys, and ShortIds.
- **Service Management**: Sets up systemd for auto-start and restart.
- **Share Link**: Outputs a standard `vless://` share link for easy import into clients (v2rayN, etc.).

## Usage

Run the following command on your VPS (Debian/Ubuntu/CentOS/Alpine/Openwrt):

```bash
bash <(curl -Ls https://raw.githubusercontent.com/obkj/xray-reality-shell/main/install.sh)
```

Follow the on-screen prompts to set the port and SNI (or press Enter for defaults).
