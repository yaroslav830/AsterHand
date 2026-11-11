<p align="center">
  <img src="docs/images/asterhand-icon.png" alt="AsterHand" width="80">
</p>

<h1 align="center">AsterHand</h1>
<p align="center"><strong>Cross-device Root control. Local device agents.</strong></p>
<p align="center">
  <a href="#windows"><kbd>Windows</kbd></a>
  <a href="#macos"><kbd>macOS</kbd></a>
  <a href="#linux"><kbd>Linux</kbd></a>
  <a href="#android"><kbd>Android</kbd></a>
  <a href="#ios"><kbd>iOS</kbd></a>
  <a href="#mcp"><kbd>MCP</kbd></a>
  <a href="#watch-it-work"><kbd>Videos</kbd></a>
</p>
<p align="center">
  <a href="README.md">English</a> ·
  <a href="README.zh-CN.md">简体中文</a> ·
  <a href="https://yaroslav830.github.io/AsterHand/">Website</a> ·
  <a href="https://github.com/yaroslav830/AsterHand/releases/tag/v1.0-build82-monorepo">Download build 82</a>
</p>

AsterHand brings the Root-authorized tools of paired Android and compatible jailbroken iOS devices into one encrypted workflow, alongside local AI workspaces, files and terminals on desktop and mobile. Connect your own ChatGPT account or OpenAI-compatible API, choose a project and an execution target, and let the agent use the tools you authorize.

**Build 82 is a preview.** Android and iOS display version 1.0; Windows remains 0.1 testing, macOS 0.1.4 and Linux 0.1.0. Individual tools depend on the operating system and receiver permissions.

![AsterHand on Windows, Linux, macOS, iOS and Android](docs/images/five-platforms-en.jpg)

Screenshot text has been translated for this English presentation.

## What you can do

- **Work with an agent:** projects, separate conversations, model selection, reasoning settings, attachments and tool progress.
- **Control another device:** LAN discovery, pairing requests, screen viewing and authorized taps, swipes or desktop input.
- **Use files and terminals:** local or remote commands, persistent terminal sessions and file operations.
- **Use device privileges:** Android Standard / ADB / Root tiers and privileged helpers for compatible jailbroken iOS.
- **Connect your AI assistant:** 22 MCP tools share the device protocol; the compact Skill supplies operating rules.
- **Use a familiar interface:** light and dark themes and Chinese, English, Japanese, Spanish and French UI.

Pairing and permissions are separate. Root, ADB, accessibility, screen recording and microphone access remain controlled by the receiving system. Features such as system overlays and continuous voice conversations vary by platform.

## Start in four steps

1. **Install** the package for your device. On macOS, grant Screen Recording and Accessibility when using those tools. On Linux, install the DEB with your package manager.
2. **Connect AI** in Settings. Complete ChatGPT authorization yourself, or configure your OpenAI-compatible endpoint, key and model.
3. **Pair devices** on a mutually reachable LAN. Search, enter a pairing code or request an IP connection. Verify the receiving device, then allow once, always allow or reject.
4. **Select a target and verify the result.** Inspect the screen before input. Start with a read-only task such as “List the files in this project without changing anything.”

Projects and conversations stay on the device. Messages, attachments and required tool results are sent to the selected AI service. A local agent executes tools locally; it does not imply a bundled offline model.

## Watch it work

### Product overview · 26 s

<!-- Attach MP4: AsterHand-Five-Platforms-Promo-EN-1080p.mp4 -->

### One MCP controller, five platforms · 26 s

<!-- Attach MP4: AsterHand-Five-Platforms-MCP-Demo-EN-1080p.mp4 -->

The demonstration presents reviewed real-device screenshots and actual command responses in sequence. The Windows receiver is an isolated instance on the same PC, and Linux runs in VMware.

<a name="download-for-your-platform"></a>

## Platform projects

Find all ten client packages in the [build 82 release](https://github.com/yaroslav830/AsterHand/releases/tag/v1.0-build82-monorepo). Download the matching OS, processor or jailbreak environment.

### Windows

Native desktop workspace, controller, receiver and local tools.

- **Downloads** — [Installer EXE](https://github.com/yaroslav830/AsterHand/releases/download/v1.0-build82-monorepo/AsterHand-Windows-Setup.exe) · [Portable EXE](https://github.com/yaroslav830/AsterHand/releases/download/v1.0-build82-monorepo/AsterHand-Windows.exe)
- **Requirements** — Windows 7 SP1 or newer; .NET Framework 4.6.2+. Native desktop client.
- **Source and docs** — `desktop/windows/` · [Platform guide](docs/platforms/windows.md)

### macOS

Intel / Apple silicon desktop agent and device tools.

- **Downloads** — [Intel](https://github.com/yaroslav830/AsterHand/releases/download/v1.0-build82-monorepo/AsterHand-0.1.4-macOS-Intel.zip) · [Apple silicon](https://github.com/yaroslav830/AsterHand/releases/download/v1.0-build82-monorepo/AsterHand-0.1.4-macOS-AppleSilicon.zip)
- **Requirements** — Intel: macOS 10.15+; Apple silicon: macOS 11+.
- **Source and docs** — `desktop/macos/` · [Platform guide](docs/platforms/macos.md)

### Linux

x64 / arm64 desktop workspace and device tools.

- **Downloads** — [x64 / amd64 DEB](https://github.com/yaroslav830/AsterHand/releases/download/v1.0-build82-monorepo/AsterHand-0.1.0-linux-amd64.deb) · [arm64 DEB](https://github.com/yaroslav830/AsterHand/releases/download/v1.0-build82-monorepo/AsterHand-0.1.0-linux-arm64.deb)
- **Requirements** — Compatible Debian/Ubuntu graphical desktop. Tested on Ubuntu 24.04 x64 in VMware.
- **Source and docs** — `desktop/linux/` · [Platform guide](docs/platforms/linux.md)

### Android

Mobile agent, paired control and Standard / ADB / Root tools.

- **Downloads** — [APK](https://github.com/yaroslav830/AsterHand/releases/download/v1.0-build82-monorepo/AsterHand-1.0-Android.apk)
- **Requirements** — Android 6.0+ build target; Standard, ADB and Root execution tiers. Development-signed preview.
- **Source and docs** — `android/` · [Platform guide](docs/platforms/android.md)

### iOS

Native app and Rootful / Rootless / RootHide helpers.

- **Downloads** — [Rootful](https://github.com/yaroslav830/AsterHand/releases/download/v1.0-build82-monorepo/AsterHand-1.0-Rootful.deb) · [Rootless](https://github.com/yaroslav830/AsterHand/releases/download/v1.0-build82-monorepo/AsterHand-1.0-Rootless.deb) · [RootHide](https://github.com/yaroslav830/AsterHand/releases/download/v1.0-build82-monorepo/AsterHand-1.0-RootHide.deb)
- **Requirements** — Compatible jailbreak required. Rootful: iOS 14+; Rootless/RootHide: iOS 15+. OpenSSH dependency declared.
- **Source and docs** — `Sources/` · [Platform guide](docs/platforms/ios.md)

### MCP

Shared protocol, MCP server, CLI and operational Skill.

Windows, macOS and Linux can host the desktop control center. MCP reuses its local connection and existing encrypted device pairings. Mobile app tools remain subject to the receiving app's capabilities and permissions.

For a source installation, keep the desktop app running, then follow the [current MCP setup instructions](mcp/README.md). The source installer requires Node.js 20+, Python 3.11+, pnpm and the Codex CLI; it preserves unrelated Codex configuration.

Example: **“List my paired AsterHand devices, confirm the target, inspect its screen, then open its settings.”**

The source is in `mcp/`. [Platform guide](docs/platforms/mcp.md)

[SHA-256 checksums](https://github.com/yaroslav830/AsterHand/releases/download/v1.0-build82-monorepo/SHA256SUMS.txt) · [Installation guide](docs/INSTALL.en.md) · [Chinese installation guide](docs/INSTALL.zh-CN.md)

Minimum versions are build targets, not proof that every device or OS release has been tested. macOS packages are ad hoc signed. Linux Wayland does not currently support local input injection; control of paired phones uses the phone's own input permissions.

Clone AsterHand once to get all five clients, the MCP tools and the website. See [projects.json](projects.json) for the component paths.

```sh
git clone https://github.com/yaroslav830/AsterHand.git
cd AsterHand
```

## Feedback and distribution

[Report a bug](https://github.com/yaroslav830/AsterHand/issues) with the client version, OS, device model, reproduction steps and a redacted screenshot. Keep passwords, keys and private conversations out of reports.

Binaries are distributed through Releases, separately from source branches. The AsterHand source repository is public. Publicly visible source is not granted an open-source license; existing third-party licenses and notices remain in force. See [SOURCE_ONLY.md](SOURCE_ONLY.md).
