# Installing AsterHand build 82

[English](INSTALL.en.md) · [简体中文](INSTALL.zh-CN.md) · [Home](../README.md)

Download from the [official build 82 release](https://github.com/yaroslav830/AsterHand/releases/tag/v1.0-build82-monorepo). All five platforms are distributed from that release, including the private-source macOS and Linux clients.

## Windows

Run `AsterHand-Windows-Setup.exe` for a per-user installation, or keep `AsterHand-Windows.exe` in a folder and run it directly. The native application requires .NET Framework 4.6.2 or newer and targets Windows 7 SP1 and newer. No separate Electron or Node.js installation is required to launch the Windows client.

## macOS

Choose the Intel ZIP for an Intel Mac or the AppleSilicon ZIP for an Apple silicon Mac. Extract the archive and move AsterHand.app to your preferred application folder.

Intel builds target macOS 10.15+; Apple silicon builds target macOS 11+. These preview builds are ad hoc signed, not notarized. If macOS requests confirmation, review the app through the normal Privacy & Security interface. Screen tools require Screen Recording and Accessibility authorization for this app. A changed application signature may require granting access to the new build again.

## Linux

Use `uname -m` to check your architecture: `x86_64` uses amd64; `aarch64` uses arm64. On a compatible Debian/Ubuntu graphical desktop:

```sh
sudo apt install ./AsterHand-0.1.0-linux-amd64.deb
asterhand
```

For arm64, replace the filename with `AsterHand-0.1.0-linux-arm64.deb`. Run the GUI as your regular user. X11 local input uses `xdotool`; Wayland does not currently support local input injection. Screen capture may show a system sharing prompt. Paired phone input follows the phone's permissions.

## Android

Install `AsterHand-1.0-Android.apk` using your system package installer. The minimum build target is Android 6.0, and this APK uses a development signature.

Choose Standard, ADB or Root in the app. Standard-mode screen assistance needs the appropriate accessibility/system grants. ADB mode requires authorized debugging; Root mode requires approval in the installed Root manager. Root is not required just to open the app.

## iOS

Choose the package that matches the active jailbreak environment:

| Environment | File | Minimum firmware |
| --- | --- | --- |
| Rootful | `AsterHand-1.0-Rootful.deb` | iOS 14 |
| Rootless | `AsterHand-1.0-Rootless.deb` | iOS 15 |
| RootHide | `AsterHand-1.0-RootHide.deb` | iOS 15 |

Open the matching DEB in your jailbreak package manager and let it resolve dependencies. All three packages declare OpenSSH. These are jailbreak packages; stock iOS is not supported.

The signed Sileo/Zebra software source is being migrated. Until the new source is deployed and verified, use the matching DEB attached to this release and follow the [iOS project instructions](https://github.com/yaroslav830/AsterHand/tree/main/apt-repo).

## Verify a download

Download `SHA256SUMS.txt` from the same release. Compare the appropriate line with your file:

```powershell
Get-FileHash .\AsterHand-Windows-Setup.exe -Algorithm SHA256
```

```sh
# macOS
shasum -a 256 AsterHand-0.1.4-macOS-Intel.zip
# Linux
sha256sum AsterHand-0.1.0-linux-amd64.deb
```

Minimum versions are build targets; they do not mean every OS/device combination has been tested. Consult the release notes for preview limitations. Grant only the tool permissions needed on the receiver.
