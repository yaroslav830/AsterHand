# AsterHand 官网

[English](README.md) · [简体中文](README.zh-CN.md)

地址：**https://yaroslav830.github.io/AsterHand/**

官网默认英文，语言按钮可切换完整页面和两段视频；`?lang=zh` 可分享中文页面。实机展示图片使用已处理的公开素材，仅保留平台标签。英文展示中的截图文字已翻译。

页面介绍跨设备 Root 控制、本机 Agent、MCP、各平台下载、iOS 软件源与首次使用流程。macOS、Linux 提供预览安装包与公开源码。Android、Windows 保留预览／测试版标识。

在主仓库根目录使用 Python 3 构建：

```sh
python scripts/build_asterhand_website.py --output build/website
python -m http.server 8785 --bind 127.0.0.1 --directory build/website
```

构建复制官网源码、`docs/images` 中两张已公开图片，以及 `website/media` 中四段中英文视频。视频由官网自身托管，不依赖 GitHub 附件访问。源码与输出不应包含安装包、设备标识、配对记录、账户信息或私钥。

`.github/workflows/website.yml` 使用 GitHub Actions 构建并部署 GitHub Pages；官网构建仅使用本合集仓库。独立的 iOS APT 网站与签名工作流由 iOS 仓库维护；新账号的软件源完成独立部署和验证前，页面只引导直接 DEB 安装。
