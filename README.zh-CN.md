<p align="center">
  <img src="docs/images/asterhand-icon.png" alt="AsterHand" width="80">
</p>

<h1 align="center">AsterHand</h1>
<p align="center"><strong>跨设备 Root 控制，本机 Agent 协同。</strong></p>
<p align="center">Windows · macOS · Linux · iOS · Android</p>
<p align="center">
  <a href="README.md">English</a> ·
  <a href="README.zh-CN.md">简体中文</a> ·
  <a href="https://yaroslav830.github.io/AsterHand/?lang=zh">官方网站</a> ·
  <a href="https://github.com/yaroslav830/AsterHand/releases/tag/v1.0-build82-monorepo">下载 build 82</a> ·
  <a href="https://github.com/yaroslav830/AsterHand/tree/main/mcp">MCP</a>
</p>

AsterHand 把已配对 Android 和兼容越狱 iOS 的 Root 授权工具带入加密跨设备工作流，并在电脑和手机提供本机 AI 工作区、文件与终端。连接自己的 ChatGPT 账户或 OpenAI 兼容 API，选择项目与执行设备，让智能体使用你已授权的工具完成任务。

**Build 82 为预览版。** Android 与 iOS 显示版本为 1.0，Windows 保持 0.1 测试版，macOS 为 0.1.4，Linux 为 0.1.0。具体工具能力取决于操作系统和接收端权限。

![Windows、Linux、macOS、iOS 与 Android 上的 AsterHand](docs/images/five-platforms-en.jpg)

## 选择你的平台

[Build 82 发布页](https://github.com/yaroslav830/AsterHand/releases/tag/v1.0-build82-monorepo)提供全部十个客户端文件的下载入口。请按系统、处理器或越狱环境选择。

| 平台 | 安装包直达 | 系统要求 |
| --- | --- | --- |
| **Windows** | [安装版 EXE](https://github.com/yaroslav830/AsterHand/releases/download/v1.0-build82-monorepo/AsterHand-Windows-Setup.exe) · [便携版 EXE](https://github.com/yaroslav830/AsterHand/releases/download/v1.0-build82-monorepo/AsterHand-Windows.exe) | Windows 7 SP1 及以上；.NET Framework 4.6.2+；原生桌面客户端。 |
| **macOS** | [Intel](https://github.com/yaroslav830/AsterHand/releases/download/v1.0-build82-monorepo/AsterHand-0.1.4-macOS-Intel.zip) · [Apple 芯片](https://github.com/yaroslav830/AsterHand/releases/download/v1.0-build82-monorepo/AsterHand-0.1.4-macOS-AppleSilicon.zip) | Intel：macOS 10.15+；Apple 芯片：macOS 11+。 |
| **Linux** | [x64 / amd64 DEB](https://github.com/yaroslav830/AsterHand/releases/download/v1.0-build82-monorepo/AsterHand-0.1.0-linux-amd64.deb) · [arm64 DEB](https://github.com/yaroslav830/AsterHand/releases/download/v1.0-build82-monorepo/AsterHand-0.1.0-linux-arm64.deb) | 兼容的 Debian / Ubuntu 图形桌面；已在 VMware Ubuntu 24.04 x64 验证。 |
| **Android** | [APK](https://github.com/yaroslav830/AsterHand/releases/download/v1.0-build82-monorepo/AsterHand-1.0-Android.apk) | 最低构建目标 Android 6.0；普通用户、ADB、Root 三级权限；开发签名预览包。 |
| **iOS** | [Rootful](https://github.com/yaroslav830/AsterHand/releases/download/v1.0-build82-monorepo/AsterHand-1.0-Rootful.deb) · [Rootless](https://github.com/yaroslav830/AsterHand/releases/download/v1.0-build82-monorepo/AsterHand-1.0-Rootless.deb) · [RootHide](https://github.com/yaroslav830/AsterHand/releases/download/v1.0-build82-monorepo/AsterHand-1.0-RootHide.deb) | 需要兼容越狱。Rootful：iOS 14+；Rootless / RootHide：iOS 15+；均声明 OpenSSH 依赖。 |

[SHA-256 校验文件](https://github.com/yaroslav830/AsterHand/releases/download/v1.0-build82-monorepo/SHA256SUMS.txt) · [安装指引](docs/INSTALL.zh-CN.md) · [English installation guide](docs/INSTALL.en.md)

最低系统版本是构建目标，不代表每款设备、每个系统版本均已实测。macOS 安装包使用临时签名。Linux Wayland 目前不支持本机输入注入；控制已配对手机时使用手机自身的输入权限。

## 可以做什么

- **使用智能体：**管理项目与独立对话，选择模型和推理深度，发送附件，查看工具进度。
- **操控另一台设备：**局域网发现、申请配对、查看屏幕，以及已授权的点击、滑动或桌面输入。
- **操作文件与终端：**本地和远程命令、持续终端会话，以及文件管理。
- **调用设备权限：**Android 普通用户 / ADB / Root 三级执行，兼容越狱 iOS 的高权限辅助服务。
- **连接 AI 助手：**22 个 MCP 工具复用设备协议，精简 Skill 提供操作规范。
- **使用统一界面：**浅色、深色主题，以及中文、英文、日文、西班牙文和法文界面。

配对与权限分别管理。Root、ADB、辅助功能、屏幕录制和麦克风仍由接收端系统授权。系统悬浮窗、连续语音等功能因平台而异。

## 四步开始

1. **安装客户端。**选择对应包；macOS 使用屏幕工具时授予屏幕录制和辅助功能权限；Linux 通过包管理器安装 DEB。
2. **连接 AI。**在设置中由本人完成 ChatGPT 授权，或填写自己的 OpenAI 兼容接口、密钥和模型。
3. **配对设备。**两端连接到可互通的局域网，通过搜索、配对码或 IP 发出申请；接收端核对后选择允许一次、始终允许或拒绝。
4. **选择目标并检查结果。**先看屏幕再输入。建议从“列出当前项目的文件，先不要修改内容”这样的只读任务开始。

项目和对话保存在设备本机；消息、附件和推理需要的工具结果会发送到所选 AI 服务。“本机 Agent”指在本机执行工具，不表示内置离线模型。

## Codex 与 MCP

[前往 AsterHand MCP →](https://github.com/yaroslav830/AsterHand/tree/main/mcp)

Windows、macOS 和 Linux 都可以运行桌面控制中心。MCP 复用其本机连接与已有的加密配对；移动端应用工具按接收端能力与权限开放。

源码安装时保持桌面应用运行，然后按[当前 MCP 安装说明](https://github.com/yaroslav830/AsterHand/blob/main/mcp/README.md)配置。源码安装器需要 Node.js 20+、Python 3.11+、pnpm 与 Codex CLI，并保留其他 Codex 配置。

可以对助手说：**“列出我已配对的 AsterHand 设备，确认目标，先查看屏幕，再打开它的设置。”**

## 看看实际效果

| | 简体中文 | English |
| --- | --- | --- |
| 产品介绍 · 26 秒 | [观看](https://yaroslav830.github.io/AsterHand/media/AsterHand-Five-Platforms-Promo-ZH-1080p.mp4) | [Watch](https://yaroslav830.github.io/AsterHand/media/AsterHand-Five-Platforms-Promo-EN-1080p.mp4) |
| 一个 MCP 控制端，五个平台 · 26 秒 | [观看](https://yaroslav830.github.io/AsterHand/media/AsterHand-Five-Platforms-MCP-Demo-ZH-1080p.mp4) | [Watch](https://yaroslav830.github.io/AsterHand/media/AsterHand-Five-Platforms-MCP-Demo-EN-1080p.mp4) |

演示依次展示已审阅的实机截图和实际命令返回结果。Windows 接收端为同一电脑上的隔离实例，Linux 运行在 VMware 中。

## 平台项目

| 组件 | 内容 | 源码 |
| --- | --- | --- |
| Windows | 原生桌面工作区、主控、被控与本机工具 | [desktop/windows/](desktop/windows/) · [说明](docs/platforms/windows.zh-CN.md) |
| macOS | Intel / Apple 芯片桌面 Agent 与设备工具 | [desktop/macos/](desktop/macos/) · [说明](docs/platforms/macos.zh-CN.md) · [公开安装包](https://github.com/yaroslav830/AsterHand/releases/tag/v1.0-build82-monorepo) |
| Linux | x64 / arm64 桌面工作区与设备工具 | [desktop/linux/](desktop/linux/) · [说明](docs/platforms/linux.zh-CN.md) · [公开安装包](https://github.com/yaroslav830/AsterHand/releases/tag/v1.0-build82-monorepo) |
| Android | 手机 Agent、配对控制及普通用户 / ADB / Root 工具 | [android/](android/) · [说明](docs/platforms/android.zh-CN.md) |
| iOS | 原生应用与 Rootful / Rootless / RootHide 辅助服务 | [Sources/](Sources/) · [说明](docs/platforms/ios.zh-CN.md) |
| MCP | 共用协议、MCP 服务、CLI 与操作 Skill | [mcp/](mcp/) · [说明](docs/platforms/mcp.zh-CN.md) |

克隆一次即可获取五个平台的源码、MCP 和官网。各组件的目录见 [projects.json](projects.json)。

```sh
git clone https://github.com/yaroslav830/AsterHand.git
cd AsterHand
```

## 反馈与发行

[反馈问题](https://github.com/yaroslav830/AsterHand/issues)时请附客户端版本、系统、机型、复现步骤及已去除隐私的截图；不要上传密码、密钥或私有对话。

安装包放在 Releases，与源码分支分别管理。AsterHand 源码仓库公开。公开可见的源码未被授予开源许可证，已有第三方许可证和声明继续有效，详见 [SOURCE_ONLY.md](SOURCE_ONLY.md)。
