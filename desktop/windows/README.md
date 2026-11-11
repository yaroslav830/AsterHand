# AsterHand for Windows 0.1

[English](README.md) · [简体中文](README.zh-CN.md)

A native Windows app with **ChatGPT** and **Generic API** connections. It has no serial-number gate, trial revalidation or license-server requirement.

## Use

- Run `AsterHand-Windows-Setup.exe` to install. The default directory is `%LOCALAPPDATA%\Programs\AsterHand`, and can be changed. Installation is for the current user and requires no administrator rights. It creates a Start menu entry and offers an optional desktop shortcut.
- Launch from the Start menu. Uninstall through Windows Installed apps or Programs and Features. Installing over an existing copy upgrades it; exit the app completely through its tray menu before upgrading or uninstalling.
- Alternatively, run the portable `AsterHand-Windows.exe`. The interface, icons, translations and tool definitions are embedded in the EXE. The main interface requires no browser, Node.js, Electron or WebView.
- For ChatGPT, open Settings → AI settings → ChatGPT → Continue with ChatGPT. Official account authorization opens the default system browser. The account owner completes sign-in and plan-usage consent, then returns to the app. You can save multiple verified accounts, refresh them or sign out.
- After ChatGPT sign-in, the app fetches visible models from the account's `/v1/models`, preserves server order and display names, and sends the server slug in requests. It does not substitute a fixed model list. Switching accounts refreshes the catalog; Refresh model list can also reload it.
- For Generic API, enter the endpoint and key, then choose Auto, Chat Completions or Responses. Refresh models from the service or enter a model ID manually. Remote endpoints require HTTPS; local models may use HTTP and an empty key.
- Projects, conversations, drafts, attachments, task queues, pairing, terminals, files and live screens use native controls. There is no floating overlay. AI tools ask for confirmation individually by default; local-screen and remote-control permissions are separate.
- Voice uses Windows-installed recognition and speech components. The microphone is activated only after the voice button is pressed.
- Closing the window leaves the app in the tray by default. Use the tray menu or Settings → Local device → Quit to exit completely.

## Data and compatibility

- Data is stored in `%APPDATA%\AsterHand\Windows`. Keys, OAuth credentials, device identity and pairings use the current user's DPAPI encryption. Saving settings preserves a `.bak` copy. Projects and imported attachments live in the `projects` subdirectory.
- Upgrades and uninstallation preserve this user data by default. Uninstallation removes the application, shortcuts and its own registry entries, without recursively deleting unrelated files from the installation directory.
- Uninstall registration is under `HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\AsterHand.Windows`; the launch path is under `HKCU\Software\Microsoft\Windows\CurrentVersion\App Paths\AsterHand.exe`.
- When first launched from this repository, the app can import the existing device identity and pairings from `.private/control/control.json` without changing that file. Existing native Windows user data remains in use.
- Targets: Windows 7 SP1 / 8.1 / 10 / 11, x86 / x64. Requires .NET Framework 4.6.2 or later and is compiled against genuine 4.6.2 reference assemblies. An original Windows 7 installation needs the runtime installed separately.
- The AnyCPU EXE prefers 32-bit execution and runs on 32-bit or 64-bit Windows. It does not elevate privileges or change the firewall. Controlling higher-privilege windows requires corresponding user permissions.
- .NET Framework 4.6.2, native features, layout, installation and launch were validated in a Windows 7 SP1 x64 Ultimate VM with a Chinese system locale. Windows 7 x86 and physical Windows 7 hardware remain untested. Consult the test reports for detailed scope.
- If .NET installation on an original Windows 7 system fails with `0x800B0109`, update Windows' trusted certificates first. The VM test used Microsoft's KB2813430 and the official certificate chain of Microsoft's installer. These changes were limited to the test VM; AsterHand's installer does not add system root certificates. [Official .NET Framework 4.6.2 download](https://dotnet.microsoft.com/download/dotnet-framework/net462).

## Build and test

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

Automated tests generate temporary credentials and account fixtures. Coverage includes OAuth state / PKCE, signature and identity verification, token refresh, callback listeners, model catalogs, streamed completion and interruption, Generic API HTTP round trips, project data, encrypted pairing, file backups, terminals and cancellation. Protocol interoperability is checked against the existing JavaScript implementation. Layout images use internal rendering; `DrawToBitmap` does not fully capture RichTextBox native painting.

The installer uses native NSIS. Build scripts use local tools verified by SHA-256 and do not globally install development tools. Installer tests use an isolated QA registry key, Start menu group and temporary user data to validate actual installation, launch, upgrade and uninstallation.

The user completes real ChatGPT authorization in the default browser. `--live-chatgpt` explicitly uses AsterHand's saved authorized account and sends fixed test messages only. Reports contain model, streaming and match results, without login credentials. This check does not rotate tokens belonging to a running app. Automated fixtures separately cover OAuth callbacks, refresh, cancellation, identity-only login and slow token exchange; passing fixtures does not prove real account revocation and refresh. Tests do not read saved Codex or browser credentials.
