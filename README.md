<div align="center">

<img src="https://github.com/hiddify/hiddify.com/blob/main/docs/assets/hiddify-app-logo.svg" width="30%" />

# VPN4TV

**VPN client for Android TV based on [Hiddify](https://github.com/hiddify/hiddify-next)**

[![Google Play](https://img.shields.io/badge/Google%20Play-VPN4TV-green?style=flat-square&logo=google-play)](https://play.google.com/store/apps/details?id=com.vpn4tv.hiddify)
[![Telegram](https://img.shields.io/badge/Telegram-@VPN4TV-blue?style=flat-square&logo=telegram)](https://t.me/VPN4TV)
[![GitHub](https://img.shields.io/github/v/release/A4E/vpn4tv_hiddify?style=flat-square&logo=github)](https://github.com/A4E/vpn4tv_hiddify/releases)

</div>

## What is VPN4TV?

VPN4TV is a fork of [Hiddify](https://github.com/hiddify/hiddify-next) optimized for **Android TV**. It provides a simple, remote-friendly interface for managing VPN connections on smart TVs and TV boxes.

Based on [Sing-box](https://github.com/SagerNet/sing-box) core v4.1.0.

## Features

- **Android TV optimized UI** with D-pad/remote control navigation
- **Easy setup via Telegram bot** (@VPN4TV_Bot) — scan QR or enter 10-digit code
- **Sing-box core v4.1.0** with support for:
  - VLESS, VMess, Reality, Trojan, Hysteria, Hysteria2, TUIC
  - XHTTP, SplitHTTP, WebSocket, gRPC, HTTP/2 transports
  - WireGuard, SSH, Shadowsocks, ShadowTLS
  - DNSTT, VayDNS, multi-resolver DNS
  - Balancer with multiple strategies
- **HWID device identification** (Remnawave compatible)
- **Subscription management** with auto-update
- **Per-app proxy** support
- Dark/light themes

## Download

| Platform | Download |
|----------|----------|
| Android TV (ARMv7) | [APK](https://github.com/A4E/vpn4tv_hiddify/releases/latest) |
| Google Play | [Play Store](https://play.google.com/store/apps/details?id=com.vpn4tv.hiddify) |

## Setup

1. Install VPN4TV on your Android TV
2. Open the app — you'll see a QR code and a 10-digit code
3. Scan the QR code with your phone or enter the code at [@VPN4TV_Bot](https://t.me/VPN4TV_bot)
4. The bot will send your VPN configuration automatically
5. Press the connect button

## Building from source

```bash
# Clone
git clone https://github.com/A4E/vpn4tv_hiddify.git
cd vpn4tv_hiddify

# Get dependencies
flutter pub get
dart run build_runner build --delete-conflicting-outputs

# Build APK (ARM for TV)
flutter build apk --target-platform android-arm,android-arm64

# Build AAB (for Play Store)
flutter build appbundle
```

Requires Flutter 3.38+, Android SDK 36, Java 17.

## Acknowledgements

- [Hiddify](https://github.com/hiddify/hiddify-next) — upstream project
- [Sing-box](https://github.com/SagerNet/sing-box) — proxy core
- [Remnawave](https://remnawave.github.io/) — panel with HWID support

## License

Same as [Hiddify](https://github.com/hiddify/hiddify-next?tab=License-1-ov-file#readme).
