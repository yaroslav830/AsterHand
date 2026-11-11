# AsterHand for Windows 0.1

[English](README.md) · [简体中文](README.zh-CN.md)

Windows 原生窗口程序。AI 服务仅保留 **ChatGPT** 与 **通用 API**；没有序列号、试用续验或授权拦截。

## 使用

- 推荐双击 `AsterHand-Windows-Setup.exe` 安装。默认安装到 `%LOCALAPPDATA%\Programs\AsterHand`，可以更改目录；只为当前用户安装，不需要管理员权限。安装程序会创建开始菜单入口，并可选创建桌面快捷方式。
- 安装后可从开始菜单启动，在 Windows“已安装的应用”或“程序和功能”中卸载。覆盖安装可升级；升级和卸载前，请从托盘菜单完全退出程序。
- 也可直接运行便携版 `AsterHand-Windows.exe`。界面、图标、翻译和工具定义均已嵌入 EXE，不需要浏览器、Node.js、Electron 或 WebView 来运行主界面。
- ChatGPT：设置 → AI 设置 → ChatGPT → Continue with ChatGPT。仅官方账户授权会打开系统默认浏览器；由用户本人完成登录和套餐用量授权，然后返回程序。可以保存多个已验证账户，刷新或退出登录。
- ChatGPT 登录后从当前账户的 `/v1/models` 获取可见模型，按服务端顺序显示名称，请求使用服务端 slug。不会内置一份固定的新旧模型名单。切换账户会重新获取；需要时点击“刷新模型列表”。
- 通用 API：填写地址和密钥，选择自动、Chat Completions 或 Responses。可以从服务端刷新模型，也可以手动填写模型 ID。HTTPS 用于远端；本机模型可以使用 HTTP，并可留空密钥。
- 项目、会话、草稿、附件、任务队列、设备配对、终端、文件与实时屏幕使用原生界面。已去除悬浮窗功能。AI 工具默认逐次确认；屏幕权限和远程控制权限独立设置。
- 语音使用 Windows 已安装的语音识别和朗读组件。点击语音按钮才启用麦克风。
- 默认关闭窗口后留在托盘。用托盘菜单或“设置 → 本机 → 退出”完全退出。

## 数据与兼容

- 数据保存在 `%APPDATA%\AsterHand\Windows`。密钥、OAuth 凭据、设备身份与配对使用当前 Windows 用户的 DPAPI 加密；保存设置时保留 `.bak`。项目和导入的附件保存在该目录的 `projects` 内。
- 升级和卸载默认保留上述用户数据。卸载仅移除程序、快捷方式及本程序的注册信息，不递归删除安装目录内的其他文件。
- 安装注册信息位于 `HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\AsterHand.Windows`；启动路径位于 `HKCU\Software\Microsoft\Windows\CurrentVersion\App Paths\AsterHand.exe`。
- 在本仓库中首次启动时，可读取并导入 `.private/control/control.json` 的原有设备身份和配对，不修改旧文件。已有 Windows 原生程序的数据继续沿用。
- 目标：Windows 7 SP1 / 8.1 / 10 / 11，x86 / x64。需要 .NET Framework 4.6.2 或更高版本；使用真正的 4.6.2 引用程序集编译。Win7 原版不包含所需运行库，需要另行安装。
- EXE 为 AnyCPU、优先 32 位，可在 32 位和 64 位 Windows 上运行。没有提升系统权限或修改防火墙。被控制的高权限窗口需要相应用户权限。
- 已在 Windows 7 SP1 x64 中文旗舰版虚拟机中验证 .NET Framework 4.6.2、原生功能、布局和实际安装启动；32 位 Win7 和 Win7 真机尚未实测。详细结果以同目录测试报告为准。
- 原版 Win7 若安装 .NET 时出现 `0x800B0109`，应先更新 Windows 的受信任证书。此次测试使用了微软 KB2813430 和微软安装包的官方证书链，然后成功安装运行库。补丁与证书只用于测试虚拟机，AsterHand 安装程序不会自行添加系统根证书。运行库官方下载页：https://dotnet.microsoft.com/download/dotnet-framework/net462 。

## 构建与测试

```powershell
python -X utf8 scripts/build_windows_desktop.py --output build/windows-native --tests
node scripts/check_windows_native.mjs build/windows-native/AsterHand.Tests.exe
build\windows-native\AsterHand.Tests.exe --layout .private\windows-native-layout
build\windows-native\AsterHand.Tests.exe --layout-unaware .private\windows-native-layout
build\windows-native\AsterHand.Tests.exe --auth-network
build\windows-native\AsterHand.Tests.exe --live-chatgpt "$env:APPDATA\AsterHand\Windows" dist\AsterHand-Windows-live-login-report.json
python -X utf8 scripts/package_windows_desktop.py --build-dir build/windows-native
python -X utf8 scripts/build_windows_installer.py
python -X utf8 scripts/check_windows_installer.py
```

自动测试使用临时生成的凭据和账户夹具，覆盖 OAuth state / PKCE、签名和身份校验、令牌刷新、回调监听、模型目录、流式完成与中断、通用 API HTTP 往返、项目数据、加密配对、文件备份、终端与取消。协议互通直接对照现有 JS 实现。布局图来自程序内部渲染，RichTextBox 的原生绘制不完整呈现在 DrawToBitmap 中。

安装包使用原生 NSIS 制作。构建脚本使用校验过 SHA-256 的本地编译工具，不向系统全局安装构建工具。安装测试使用独立 QA 注册表键、开始菜单组和临时用户数据，验证实际安装、启动、升级和卸载。

真实 ChatGPT 授权由用户在系统默认浏览器中完成。`--live-chatgpt` 显式使用 AsterHand 自身保存的已授权账号，仅发送固定测试消息；报告记录模型、流式完成和匹配结果，不记录登录凭据。这个检查不会为仍在运行的程序轮换令牌。OAuth 回调、刷新、取消、仅身份登录及慢速令牌交换另有自动夹具验证；夹具通过不代表真实账户撤销和刷新均已实测。没有读取 Codex 或浏览器保存的登录凭据。
