# xray-onekey-script

A simple and efficient one-key deployment script for Xray supporting both **VLESS-Reality** and **VMess** protocols.

This script automates the installation of Xray-core, generates necessary credentials, and configures the service for optimal performance and security.

## Features

- **Dual Protocol Support**: Automatically sets up both VLESS (Reality) and VMess inbounds.
- **Auto-Install**: Automatically downloads the latest Xray-core.
- **Reality Config**: Configures VLESS with XTLS-Vision and Reality security.
- **Key Generation**: Automatically generates UUIDs, Private/Public keys, and ShortIds.
- **Service Management**: Sets up systemd for auto-start and restart.
- **High Port Randomization**: Generates random high-range ports (>50000) for better concealment.
- **Share Links**: Outputs standard `vless://` and `vmess://` share links and QR codes.

## Usage

Run the following command on your VPS (Debian/Ubuntu/CentOS/Alpine/Openwrt):

```bash
bash <(curl -Ls https://raw.githubusercontent.com/obkj/xray-onekey-script/main/install.sh)
```

Follow the on-screen prompts to set the port and SNI (or press Enter for defaults).
