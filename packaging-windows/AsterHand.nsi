Unicode true
RequestExecutionLevel user
ManifestDPIAware true
!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "WinVer.nsh"
!include "x64.nsh"
!include "FileFunc.nsh"

!ifndef APP_ID
!define APP_ID "AsterHand.Windows"
!endif
!ifndef APP_NAME
!define APP_NAME "AsterHand"
!endif
!ifndef APP_ALIAS
!define APP_ALIAS "AsterHand.exe"
!endif
!define UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_ID}"
!define APP_PATH_KEY "Software\Microsoft\Windows\CurrentVersion\App Paths\${APP_ALIAS}"
Name "${APP_NAME} for Windows"
OutFile "${OUTPUT}"
InstallDir "$LOCALAPPDATA\Programs\${APP_NAME}"
InstallDirRegKey HKCU "${UNINSTALL_KEY}" "InstallLocation"
BrandingText "AsterHand · Native Windows"
SetCompressor /SOLID lzma
CRCCheck force
ShowInstDetails show
ShowUninstDetails show
VIProductVersion "${VERSION}"
VIAddVersionKey /LANG=1033 "ProductName" "${APP_NAME} for Windows"
VIAddVersionKey /LANG=1033 "FileDescription" "AsterHand Windows Setup"
VIAddVersionKey /LANG=1033 "FileVersion" "${VERSION}"
VIAddVersionKey /LANG=1033 "ProductVersion" "${VERSION}"
VIAddVersionKey /LANG=1033 "LegalCopyright" "AsterHand"
!define MUI_ICON "${ICON}"
!define MUI_UNICON "${ICON}"
!define MUI_ABORTWARNING
!define MUI_WELCOMEPAGE_TITLE "$(WelcomeTitle)"
!define MUI_WELCOMEPAGE_TEXT "$(WelcomeBody)"
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_RUN "$INSTDIR\AsterHand.exe"
!define MUI_FINISHPAGE_RUN_NOTCHECKED
!define MUI_FINISHPAGE_RUN_TEXT "$(FinishRun)"
!insertmacro MUI_PAGE_FINISH
!define MUI_UNCONFIRMPAGE_TEXT_TOP "$(UninstallBody)"
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_UNPAGE_FINISH
!insertmacro MUI_LANGUAGE "English"
!insertmacro MUI_LANGUAGE "SimpChinese"

; NSIS selects a supported system language; the first language is the fallback.
LangString WelcomeTitle ${LANG_ENGLISH} "Install ${APP_NAME} for Windows"
LangString WelcomeTitle ${LANG_SIMPCHINESE} "安装 ${APP_NAME} for Windows"
LangString WelcomeBody ${LANG_ENGLISH} "Native Windows client: ChatGPT, Generic API, projects, files, terminals, and device connections.$\r$\n$\r$\nInstalls for the current Windows user without administrator rights. Projects, pairings, and sign-in data are preserved.$\r$\n$\r$\nRequires Windows 7 SP1 or later and .NET Framework 4.6.2 or later."
LangString WelcomeBody ${LANG_SIMPCHINESE} "原生 Windows 客户端：ChatGPT、通用 API、项目、文件、终端与设备连接。$\r$\n$\r$\n安装到当前 Windows 用户，不需要管理员权限。项目、配对与登录数据会继续保留。$\r$\n$\r$\n系统要求：Windows 7 SP1 或更高版本，以及 .NET Framework 4.6.2 或更高版本。"
LangString FinishRun ${LANG_ENGLISH} "Launch ${APP_NAME}"
LangString FinishRun ${LANG_SIMPCHINESE} "启动 ${APP_NAME}"
LangString UninstallBody ${LANG_ENGLISH} "Removes the AsterHand application, shortcuts, and its registry entries.$\r$\n$\r$\nProjects, attachments, device pairings, and sign-in data remain in AppData. Exit AsterHand completely from its tray menu first."
LangString UninstallBody ${LANG_SIMPCHINESE} "将移除 AsterHand 程序、快捷方式和注册表信息。$\r$\n$\r$\n项目、附件、设备配对和登录数据会保留在 AppData 中。请先从托盘菜单完全退出 AsterHand。"
LangString RequiresWindows ${LANG_ENGLISH} "Windows 7 SP1 or later is required."
LangString RequiresWindows ${LANG_SIMPCHINESE} "需要 Windows 7 SP1 或更高版本。"
LangString RequiresDotnet ${LANG_ENGLISH} ".NET Framework 4.6.2 or later is required. Open Microsoft's official download page in your default browser?$\r$\n$\r$\nRun this installer again after installing the runtime. Windows 10 / 11 usually includes a compatible runtime."
LangString RequiresDotnet ${LANG_SIMPCHINESE} "需要 .NET Framework 4.6.2 或更高版本。是否用系统默认浏览器打开微软官方下载页面？$\r$\n$\r$\n运行库安装完成后，请重新运行本安装程序。Windows 10 / 11 通常已包含兼容运行库。"
LangString MainSection ${LANG_ENGLISH} "Application and Start menu (required)"
LangString MainSection ${LANG_SIMPCHINESE} "主程序与开始菜单（必需）"
LangString DesktopSection ${LANG_ENGLISH} "Desktop shortcut"
LangString DesktopSection ${LANG_SIMPCHINESE} "桌面快捷方式"
LangString AppBusyInstall ${LANG_ENGLISH} "AsterHand is running. Exit it completely from the tray menu, then run the installer again."
LangString AppBusyInstall ${LANG_SIMPCHINESE} "AsterHand 正在运行。请从托盘菜单完全退出后，再重新安装。"
LangString InstallInfoMismatch ${LANG_ENGLISH} "Installation information does not match. Uninstallation was stopped."
LangString InstallInfoMismatch ${LANG_SIMPCHINESE} "安装信息不匹配，已停止卸载。"
LangString UninstallDirMismatch ${LANG_ENGLISH} "The uninstall directory does not match. Uninstallation was stopped."
LangString UninstallDirMismatch ${LANG_SIMPCHINESE} "卸载目录不匹配，已停止卸载。"
LangString UninstallShortcut ${LANG_ENGLISH} "Uninstall ${APP_NAME}"
LangString UninstallShortcut ${LANG_SIMPCHINESE} "卸载 ${APP_NAME}"
LangString UninstallDataRetained ${LANG_ENGLISH} "Projects, attachments, pairings, and sign-in data were preserved in AppData."
LangString UninstallDataRetained ${LANG_SIMPCHINESE} "项目、附件、配对和登录数据已保留在 AppData。"
LangString AppBusyUninstall ${LANG_ENGLISH} "Exit AsterHand from its tray menu, then run the uninstaller again."
LangString AppBusyUninstall ${LANG_SIMPCHINESE} "请先从托盘菜单退出 AsterHand，再重新卸载。"

Function .onInit
  SetShellVarContext current
  ${IfNot} ${AtLeastWin7}
    MessageBox MB_ICONSTOP "$(RequiresWindows)" /SD IDOK
    Abort
  ${EndIf}
  SetRegView 32
  ReadRegDWORD $0 HKLM "SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" "Release"
  ${If} $0 < 394802
    MessageBox MB_YESNO|MB_ICONEXCLAMATION "$(RequiresDotnet)" /SD IDNO IDNO runtime_missing
    ExecShell "open" "https://dotnet.microsoft.com/download/dotnet-framework/net462"
runtime_missing:
    SetErrorLevel 3
    Abort
  ${EndIf}
FunctionEnd

Function .onVerifyInstDir
  ${GetRoot} "$INSTDIR" $0
  StrCmp "$INSTDIR" "$0\" invalid
  StrCmp "$INSTDIR" "$WINDIR" invalid
  StrCmp "$INSTDIR" "$SYSDIR" invalid
  StrCmp "$INSTDIR" "$PROFILE" invalid
  StrCmp "$INSTDIR" "$LOCALAPPDATA" invalid
  StrCmp "$INSTDIR" "$PROGRAMFILES" invalid
  IfFileExists "$INSTDIR\install-info.ini" owned done
owned:
  ReadINIStr $0 "$INSTDIR\install-info.ini" "Application" "Product"
  StrCmp "$0" "${APP_ID}" done invalid
invalid:
  Abort
done:
FunctionEnd

Section "$(MainSection)" Main
  SectionIn RO
  SetShellVarContext current
  SetRegView 32
  CreateDirectory "$INSTDIR"
  IfFileExists "$INSTDIR\AsterHand.exe" 0 extract
  ClearErrors
  FileOpen $0 "$INSTDIR\AsterHand.exe" a
  IfErrors busy
  FileClose $0
extract:
  SetOutPath "$INSTDIR"
  SetOverwrite on
  File /oname=AsterHand.exe "${PAYLOAD}"
  File /oname=README.md "${README}"
  File /oname=README.zh-CN.md "${README_ZH}"
  Delete "$INSTDIR\使用说明.txt"
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  WriteINIStr "$INSTDIR\install-info.ini" "Application" "Product" "${APP_ID}"
  WriteINIStr "$INSTDIR\install-info.ini" "Application" "Version" "${VERSION}"
  WriteINIStr "$INSTDIR\install-info.ini" "Application" "Directory" "$INSTDIR"
  CreateDirectory "$SMPROGRAMS\${APP_NAME}"
  CreateShortcut "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk" "$INSTDIR\AsterHand.exe" "" "$INSTDIR\AsterHand.exe" 0
  Delete "$SMPROGRAMS\${APP_NAME}\Uninstall ${APP_NAME}.lnk"
  Delete "$SMPROGRAMS\${APP_NAME}\卸载 ${APP_NAME}.lnk"
  CreateShortcut "$SMPROGRAMS\${APP_NAME}\$(UninstallShortcut).lnk" "$INSTDIR\Uninstall.exe"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayName" "${APP_NAME} for Windows"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "Publisher" "AsterHand"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayIcon" "$INSTDIR\AsterHand.exe,0"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "UninstallString" '$\"$INSTDIR\Uninstall.exe$\"'
  WriteRegStr HKCU "${UNINSTALL_KEY}" "QuietUninstallString" '$\"$INSTDIR\Uninstall.exe$\" /S'
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoRepair" 1
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "EstimatedSize" 2048
  WriteRegStr HKCU "${APP_PATH_KEY}" "" "$INSTDIR\AsterHand.exe"
  WriteRegStr HKCU "${APP_PATH_KEY}" "Path" "$INSTDIR"
  Goto finished
busy:
  MessageBox MB_ICONEXCLAMATION "$(AppBusyInstall)" /SD IDOK
  SetErrorLevel 2
  Abort
finished:
SectionEnd

Section /o "$(DesktopSection)" Desktop
  SetShellVarContext current
  CreateShortcut "$DESKTOP\${APP_NAME}.lnk" "$INSTDIR\AsterHand.exe" "" "$INSTDIR\AsterHand.exe" 0
SectionEnd

Function un.onInit
  SetShellVarContext current
  SetRegView 32
  ReadINIStr $0 "$INSTDIR\install-info.ini" "Application" "Product"
  StrCmp "$0" "${APP_ID}" +3
  MessageBox MB_ICONSTOP "$(InstallInfoMismatch)" /SD IDOK
  Abort
  ReadINIStr $0 "$INSTDIR\install-info.ini" "Application" "Directory"
  StrCmp "$0" "$INSTDIR" +3
  MessageBox MB_ICONSTOP "$(UninstallDirMismatch)" /SD IDOK
  Abort
FunctionEnd

Section "Uninstall"
  SetShellVarContext current
  SetRegView 32
  ClearErrors
  Delete "$INSTDIR\AsterHand.exe"
  IfErrors busy
  ReadRegStr $0 HKCU "${UNINSTALL_KEY}" "InstallLocation"
  StrCmp "$0" "$INSTDIR" 0 files
  Delete "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk"
  Delete "$SMPROGRAMS\${APP_NAME}\Uninstall ${APP_NAME}.lnk"
  Delete "$SMPROGRAMS\${APP_NAME}\卸载 ${APP_NAME}.lnk"
  RMDir "$SMPROGRAMS\${APP_NAME}"
  Delete "$DESKTOP\${APP_NAME}.lnk"
  DeleteRegKey HKCU "${UNINSTALL_KEY}"
  DeleteRegKey HKCU "${APP_PATH_KEY}"
files:
  Delete "$INSTDIR\README.md"
  Delete "$INSTDIR\README.zh-CN.md"
  Delete "$INSTDIR\使用说明.txt"
  Delete "$INSTDIR\install-info.ini"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
  DetailPrint "$(UninstallDataRetained)"
  Goto done
busy:
  MessageBox MB_ICONEXCLAMATION "$(AppBusyUninstall)" /SD IDOK
  SetErrorLevel 2
  Abort
done:
SectionEnd
