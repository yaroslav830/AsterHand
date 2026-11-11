# AsterHand iOS 越狱软件源

[English](README.md) · [简体中文](README.zh-CN.md)

> **软件源迁移中。** 可从[主项目发布页](https://github.com/yaroslav830/AsterHand/releases/tag/v1.0-build82-monorepo)下载对应 DEB。以下软件源安装步骤适用于签名软件源部署成功后。

**[规划中的软件源页面](https://yaroslav830.github.io/AsterHand/ios-apt/)**

## 从软件源安装

1. 在设备已有终端执行 `dpkg --print-architecture`，只读取引导架构，不修改设置。
2. 在 Sileo／Zebra → 软件源 → 添加，填入下表对应地址。网页也有一键跳转，旧版 Cydia 使用 Rootful 源。
3. 刷新源，搜索 **AsterHand**，点击**获取／安装**，检查依赖队列后确认。各环境独立源已包含 OpenSSH 及其运行依赖。
4. 打开 AsterHand，连接自己的 AI 服务，按需启用 Root 和屏幕权限。后续刷新包管理器并确认升级即可更新。

| 越狱环境 | dpkg 架构 | 软件源地址 | AsterHand 最低目标 |
| --- | --- | --- | --- |
| Rootful／Elucubratus | `iphoneos-arm` | `https://yaroslav830.github.io/AsterHand/ios-apt/rootful/` | iOS 14 |
| Rootless | `iphoneos-arm64` | `https://yaroslav830.github.io/AsterHand/ios-apt/rootless/` | iOS 15 |
| RootHide | `iphoneos-arm64e` | `https://yaroslav830.github.io/AsterHand/ios-apt/roothide/` | iOS 15 |

这些架构表示引导布局，不是 CPU ABI。**Procursus Rootful 用户**请保留引导自带的 OpenSSH，并使用[仅提供 AsterHand 的统一源](https://yaroslav830.github.io/AsterHand/ios-apt/)，不要为安装应用替换越狱引导。

统一平铺源由 Sileo／Zebra 自动选择原生 AsterHand DEB，依赖仍由现有引导源提供。上游标为 `Architecture: all` 的包也可能包含环境专属路径，所以完整 OpenSSH 依赖放在各环境独立源中，不修改原包字节或架构。

添加源不会安装软件或授予 Root。安装 OpenSSH 后，上游包可能启动 SSH 服务，请配置登录凭据或 SSH 密钥。Safari 只能识别系统版本，不能确定越狱环境；可选[只读脚本](detect-environment.sh)会查询实际 dpkg 架构。

## 自动保持最新

当前保留[软件源工作流参考](ios-apt-workflow.example.yml)。恢复发布时，将签名后的软件源放到官网构建产物的 ios-apt/ 目录，由同一次 Pages 部署发布。更新机制如下。

- AsterHand 跟随本仓库的 **GitHub 最新正式 Release**，必须有三个环境的匹配 DEB，并校验 SHA-256、大小、包标识、版本、最低系统和架构。不把任意源码提交当作安装版。
- OpenSSH 跟随 Elucubratus、Procursus iOS 15 基线、RootHide iOS 15 基线中最新的**已打包稳定版本**，按 Debian 版本规则解析 `Depends`／`Pre-Depends`。固件、dpkg 和 RootHide 本身仍由原引导提供，不替换为不兼容的新版上游源码。
- 保留上游原包、维护者、许可证、相关源码材料和 SHA-256 来源记录。四组索引使用现有密钥签名；下载或校验失败即停止部署，线上源保持原样。拒绝 AsterHand 降级及同版本换包字节，发布可升级的新包必须提高 DEB 的 `Version`。

自动更新的是软件源，设备仍需刷新并确认升级。GitHub 定时运行可能延迟，长期无活动时可能被停用，详见[定时任务说明](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule)。

[线上软件包来源记录](https://yaroslav830.github.io/AsterHand/ios-apt/upstream-packages.json) · [第三方声明与源码材料](https://yaroslav830.github.io/AsterHand/ios-apt/third-party/README.md)

## 本地重建与签名

需要 Python **3.14+** 和 GnuPG。私钥目录放在源码管理和公开站点之外。Actions Secret `APT_SIGNING_PRIVATE_KEY` 只保存现有专用 APT 签名私钥，不保存个人 GitHub Token 或其他私钥；不在外部 PR 上触发。工作流只有 Pages 部署权限，不需要源码写权限；GitHub Pages 发布来源设为 **GitHub Actions**。

```sh
python -m unittest discover -s tests -p test_ios_apt_common.py
python scripts/sync_ios_apt_upstreams.py --output build/apt-artifacts
python scripts/collect_ios_apt_notices.py build/apt-artifacts
python scripts/build_ios_apt_repo.py --artifacts build/apt-artifacts --dependencies build/apt-artifacts/dependencies.json --output build/ios-apt-site --gpg-home .private/apt-signing --key 457D056969DE0D9DB31C0259025BDCAD4FDCD88C
python scripts/check_ios_apt_repo.py build/ios-apt-site
```

本地可用 `--release-json`、`--roothide-commit` 指定 GitHub 元数据快照，Windows 可通过 `--gpg`／`--gpgv` 指定 Git for Windows 工具路径。只部署生成的站点。签名指纹保持为 **457D056969DE0D9DB31C0259025BDCAD4FDCD88C**。手动配置 APT 应使用公钥和 `Signed-By`，不要关闭签名校验。
