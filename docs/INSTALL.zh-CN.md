# 安装 AsterHand build 82

[English](INSTALL.en.md) · [简体中文](INSTALL.zh-CN.md) · [主页](../README.zh-CN.md)

从[官方 build 82 发布页](https://github.com/yaroslav830/AsterHand/releases/tag/v1.0-build82-monorepo)下载。五个平台均在同一发布页提供，包含源码保持私有的 macOS 与 Linux 客户端。

## Windows

运行 `AsterHand-Windows-Setup.exe` 安装到当前用户，或把 `AsterHand-Windows.exe` 放在一个文件夹中直接运行。原生客户端最低构建目标为 Windows 7 SP1，需要 .NET Framework 4.6.2 或更高版本；启动 Windows 客户端不需另装 Electron 或 Node.js。

## macOS

Intel Mac 选择 Intel ZIP，Apple 芯片 Mac 选择 AppleSilicon ZIP。解压后把 AsterHand.app 移到准备存放应用的位置。

Intel 版最低目标 macOS 10.15，Apple 芯片版为 macOS 11。这些预览包使用临时签名，尚未公证；若系统要求确认，请在常规“隐私与安全性”页面核对应用。使用屏幕工具需为此应用授予屏幕录制与辅助功能权限；应用签名变化后可能需要重新授权新版。

## Linux

先用 `uname -m` 确认架构：`x86_64` 选 amd64，`aarch64` 选 arm64。在兼容的 Debian / Ubuntu 图形桌面中安装：

```sh
sudo apt install ./AsterHand-0.1.0-linux-amd64.deb
asterhand
```

arm64 将文件名换为 `AsterHand-0.1.0-linux-arm64.deb`。用普通用户运行图形客户端。X11 本机输入需要 `xdotool`；Wayland 目前不支持本机输入注入，截图可能显示系统共享选择框。操作已配对手机时遵循手机自身权限。

## Android

使用系统安装器安装 `AsterHand-1.0-Android.apk`。最低构建目标 Android 6.0，当前 APK 使用开发签名。

在应用中选择普通用户、ADB 或 Root。普通模式的屏幕助手需相应的辅助功能和系统授权；ADB 需调试授权；Root 需在设备已有的 Root 管理器中允许。仅打开应用不要求 Root。

## iOS

按当前越狱环境选择安装包：

| 环境 | 文件 | 最低固件 |
| --- | --- | --- |
| Rootful | `AsterHand-1.0-Rootful.deb` | iOS 14 |
| Rootless | `AsterHand-1.0-Rootless.deb` | iOS 15 |
| RootHide | `AsterHand-1.0-RootHide.deb` | iOS 15 |

用越狱包管理器打开对应 DEB，并由包管理器处理依赖。三个包均声明 OpenSSH 依赖，需要匹配的越狱环境，不支持未越狱 iOS。

Sileo / Zebra 签名软件源正在迁移。在新软件源完成部署和验证前，请使用本次 Release 附件中对应环境的 DEB，并参阅 [iOS 项目安装说明](https://github.com/yaroslav830/AsterHand/tree/main/apt-repo)。

## 校验下载文件

从同一发布页下载 `SHA256SUMS.txt`，将对应行与本地结果比较：

```powershell
Get-FileHash .\AsterHand-Windows-Setup.exe -Algorithm SHA256
```

```sh
# macOS
shasum -a 256 AsterHand-0.1.4-macOS-Intel.zip
# Linux
sha256sum AsterHand-0.1.0-linux-amd64.deb
```

最低系统版本是构建目标，不代表所有机型与系统组合均已验证。预览版限制见发布说明，在接收端开启实际需要的工具权限即可。
