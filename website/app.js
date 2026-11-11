'use strict';

const translations = {
  'skip':'跳转到正文',
  'nav.product':'产品能力','nav.platforms':'平台与下载','nav.guide':'开始使用','nav.menu':'菜单',
  'hero.release':'ASTERHAND 1.0 现已发布','hero.preview':'Windows · macOS · Linux · iOS · Android',
  'hero.title1':'跨设备，','hero.title2':'调用 Root<br>真正的能力。',
  'hero.description':'将手机已授权的 Root 工具带入跨设备工作流。远程操控、本机 Agent，或通过 MCP 连接你的 AI 助手，让设备协同完成任务。',
  'hero.download':'获取 AsterHand','hero.demo':'观看实际演示','hero.workflow':'你的设备，共同协作。',
  'hero.paired':'加密配对','hero.caption':'应用实机截图 · 展示标签已处理为英文',
  'strip.eyebrow':'连接设备，也连接工具','strip.root':'Root 与 ADB','strip.screen':'屏幕操控','strip.terminal':'文件与终端','strip.agent':'本机 Agent',
  'product.eyebrow':'01 / 围绕真实设备工具构建','product.title':'能力在设备上，<br>协作不止于设备。',
  'product.intro':'AsterHand 连接设备已有的能力。选择任务执行的位置，使用你授予的工具，并确认每一步的结果。',
  'product.rootLabel':'跨设备 ROOT 控制','product.rootTitle':'屏幕背后，<br>还有更多工具。',
  'product.rootBody':'在已配对的 Android 或兼容越狱 iOS 设备上，调用 Root 命令、文件与系统工具，再配合屏幕查看和输入完成操作。',
  'product.localTitle':'Agent，就在设备上。','product.localBody':'在手机或电脑上管理项目与对话。由你选择的 AI 服务推理，本机 Agent 通过可用的设备工具执行任务。',
  'product.pairTitle':'完成配对，选择执行目标。','product.pairBody':'在可互通的局域网中发现设备，核对配对信息并确认连接。控制端与接收端通过加密配对协作。',
  'product.permissionsTitle':'权限始终由接收设备决定。','product.permissionsBody':'Root、ADB、AI 屏幕访问与远程屏幕访问分别授权。配对本身不会开启这些权限。',
  'demo.eyebrow':'02 / 看见完整工作流','demo.title':'从一句请求，<br>到设备执行结果。',
  'demo.intro':'产品介绍与五平台 MCP 演示均有中英文版本。',
  'demo.rootLabel':'CODEX + MCP / 五平台验证','demo.rootTitle':'一个控制端，五个平台。',
  'demo.rootBody':'同一 Windows 控制端通过 MCP 连接 Windows、Linux、macOS、iOS、Android。Windows 为同机隔离接收端，Linux 运行在 VMware。',
  'demo.recording':'画面采用审核后的设备截图，并依次呈现实际命令返回结果。英文展示版的截图文字已翻译为英文。',
  'demo.overviewLabel':'认识 ASTERHAND',
  'demo.overviewTitle':'用一个短片，了解 AsterHand。','demo.overviewBody':'五个平台共享设备协议，提供本机 Agent 与 MCP 工具。',
  "mcp.eyebrow": "ASTERHAND MCP",'mcp.title':'给 AI 助手，<br>一套设备工具。',
  'mcp.body':'将 Codex 或其他支持 MCP 的助手连接到已配对设备。查看屏幕、操作文件与终端，或向手机 Agent 委派任务。',
  'mcp.count':'个 MCP 工具 · 遵循接收端既有权限','mcp.example':'请求示例',
  'mcp.prompt':'“找到我已配对的手机，查看屏幕，再列出项目里的文件。”',
  'mcp.step1':'选定准确的已配对设备','mcp.step2':'检查当前屏幕','mcp.step3':'使用接收端允许的工具','mcp.step4':'委派任务并跟进执行进度',
  "guide.title": "安装与使用教程",
  'faq.eyebrow':'连接之前，先了解这些','faq.title':'你可能想知道。',
  'faq.q1':'AsterHand 会给设备获取 Root 或越狱吗？','faq.a1':'不会。AsterHand 使用你已经开启并授权的 Root、ADB、越狱辅助服务和屏幕能力，不执行越狱，也不会通过配对获取这些权限。',
  'faq.q2':'“本机 Agent”包含离线 AI 模型吗？','faq.a2':'Agent 在设备上执行工具，模型推理由你选择的 AI 服务提供，应用没有捆绑离线模型。推理所需的消息、附件和工具结果会发送给所选服务。',
  'faq.q3':'应该选择哪个 iOS 安装包？','faq.a3':'在设备已有终端中执行 dpkg --print-architecture。iphoneos-arm 对应 Rootful，iphoneos-arm64 对应 Rootless，iphoneos-arm64e 对应 RootHide。当前 AsterHand 最低目标为 Rootful iOS 14+、Rootless／RootHide iOS 15+，最低目标不代表已验证所有越狱组合。',
  'faq.q4':'在哪里获取源码和发布文件？','faq.a4':'源码与各平台文档位于 GitHub，可用客户端安装包在主项目的 Releases 中。AsterHand 原创代码未授予开源许可；第三方声明与许可证继续有效。',
  'closing.title':'让你的设备，<br>共同完成任务。','closing.github':'浏览主项目',
  'footer.tagline':'跨设备 Root 控制，本机 Agent 协同。','footer.repo':'iOS 安装说明','footer.version':'Build 82 / 1.0 / Windows 0.1 测试版',
  "ios.aptTitle": "通过签名软件源安装",
  "ios.apt1": "在设备终端执行 <code>dpkg --print-architecture</code>，确认当前越狱环境。",
  "ios.apt2": "在 Sileo 或 Zebra 打开「软件源 → 添加软件源」，粘贴下方对应地址。",
  "ios.apt3": "刷新软件源并搜索 AsterHand，核对安装队列中的 AsterHand 和 OpenSSH 依赖，确认安装后启动应用。之后检查更新时，在包管理器内重新刷新软件源。",
  "ios.procursus": "Procursus Rootful 保留引导环境自带的 OpenSSH，添加统一 AsterHand 软件源 <code>https://yaroslav830.github.io/AsterHand/ios-apt/</code>。",
  "windows.requirements": "0.1 测试版 · Windows 7 SP1 或更高版本 · .NET Framework 4.6.2 或更高版本",
  "windows.install1": "运行 <code>AsterHand-Windows-Setup.exe</code> 为当前 Windows 用户安装，再打开 AsterHand。若使用便携版，将 <code>AsterHand-Windows.exe</code> 保存到自己有写入权限的文件夹后直接运行。",
  "windows.install2": "打开 AsterHand，在设置中配置 AI 连接，再到「远程连接」发现并配对接收设备。",
  "windows.installer": "下载安装版",
  "windows.portable": "下载便携版 EXE",
  "macos.requirements": "0.1.4 预览版 · Intel：macOS 10.15+ · Apple 芯片：macOS 11+",
  "macos.install1": "在苹果菜单 →「关于本机」查看芯片或处理器。下载匹配的 ZIP，解压后将 <code>AsterHand.app</code> 移到「应用程序」，再从那里打开。",
  "macos.install2": "预览版使用临时签名。若 macOS 要求核对应用，请进入「系统设置 → 隐私与安全性」。查看和控制屏幕时，按需授予屏幕录制及辅助功能权限。更新后可能需要重新授权。",
  "macos.intel": "下载 Intel ZIP",
  "macos.apple": "下载 Apple 芯片 ZIP",
  "linux.filename": "arm64 设备请在第一条命令中使用 <code>AsterHand-0.1.0-linux-arm64.deb</code>。",
  "linux.requirements": "0.1.0 预览版 · Debian／Ubuntu 图形桌面 · amd64 或 arm64",
  "linux.install1": "运行 <code>uname -m</code> 查看处理器架构。<code>x86_64</code> 选 amd64，<code>aarch64</code> 选 arm64。",
  "linux.install2": "使用包管理器安装 DEB，或在下载目录执行下方命令。以普通用户启动图形界面。",
  "linux.install3": "X11 本机输入依赖 <code>xdotool</code>。Wayland 目前不支持本机输入注入，截图可能需要在系统对话框选择共享内容。已配对手机使用手机自身的输入权限。",
  "linux.amd64": "下载 amd64 DEB",
  "linux.arm64": "下载 arm64 DEB",
  "android.requirements": "1.0 预览版 · 最低构建目标 Android 6.0 · 开发签名 APK",
  "android.install1": "下载 <code>AsterHand-1.0-Android.apk</code>，用 Android 系统安装器打开。",
  "android.install2": "在 AsterHand 选择普通用户、ADB 或 Root 模式。普通模式需对应的屏幕和辅助功能权限。ADB 需要调试授权。Root 模式请在设备已有的 Root 管理器中批准。",
  "android.apk": "下载 APK",
  "ios.requirements": "1.0 预览版 · 需要兼容越狱 · Rootful iOS 14+ · Rootless 和 RootHide iOS 15+",
  "ios.install1": "手动安装时，按当前越狱环境选择 DEB，在 Sileo 或 Zebra 打开，核对安装队列后确认。三个安装包都声明了 OpenSSH 依赖。",
  "ios.install2": "打开 AsterHand，配置 AI 连接，并按需启用屏幕与 Root 权限。",
  "ios.rootful": "下载 Rootful DEB",
  "ios.rootless": "下载 Rootless DEB",
  "ios.roothide": "下载 RootHide DEB",
  "verify.title": "校验安装包",
  "verify.intro": "运行与你的系统对应的命令，并对照校验文件中的同名条目。",
  "verify.download": "下载 SHA256SUMS.txt",
  "platform.eyebrow": "各平台安装",
  "platform.title": "安装 AsterHand",
  "platform.intro": "按操作系统、处理器或越狱环境选择安装包，安装后再检查远程连接与接收端权限。",
  "mcp.installTitle": "安装并测试 AsterHand MCP",
  "mcp.install1": "从源码安装时，准备 Node.js 20+、Python 3.11+、pnpm 和 Codex CLI。执行下方命令克隆并安装。如果已有源码，在仓库根目录执行最后一行即可。安装器会注册 <code>asterhand</code> 并保留其他 MCP 条目。",
  "mcp.install2": "使用 macOS 应用安装包时，可以运行自带的安装器。在 Finder 对 AsterHand.app 选择「显示包内容」，打开 Contents → Resources，运行 <code>Install Codex MCP.command</code>。",
  "mcp.install3": "打开新的 Codex 对话，请它调用 <code>devices_list</code>。用 <code>device_info</code> 核对准确的设备，再用 <code>screenshot</code> 查看屏幕。先测试只读任务，再到设备上核对结果。",
  "mcp.installNote": "屏幕、ADB 和 Root 操作仍由接收端权限决定。",
  "faq.iosLink": "查看本页 iOS 安装引导",
  "windows.check": "若应用无法启动，检查是否安装 .NET Framework 4.6.2 或更高版本。若应用能启动但接收端无法连接，检查两端的「远程连接」，确认局域网可互通。",
  "macos.check": "授权后返回 AsterHand，在设置中检查权限状态，再测试本机截图。若 macOS 提示退出后重新打开，请按提示重开再测试。",
  "linux.check": "若应用可打开但 Wayland 无法截图，检查 PipeWire、<code>xdg-desktop-portal</code> 和桌面环境对应的门户服务。桌面出现共享提示时，选择对应屏幕或窗口。",
  "android.check": "先在所选权限等级下测试只读操作。若已配对但屏幕工具不可用，在手机上检查所需的系统屏幕权限以及 AsterHand 的远程屏幕设置。",
  "ios.check": "若包管理器提示固件或架构不匹配，按下方命令检查架构，改用当前越狱引导环境对应的包。若有依赖无法解析，先在包管理器里核对。",
  "mcp.guideIntro": "MCP 通过 Windows、macOS 或 Linux 上的 AsterHand 控制中心连接设备，可使用已配对的 Android 和 iOS 接收端。先打开 AsterHand，再确认接收设备在线。",
  "mcp.install4": "如果工具没有出现，检查 Codex 是否已注册 <code>asterhand</code>，再重新打开对话。若工具可见但接收端离线，检查桌面控制中心是否运行，以及能否连接已配对设备。",
  "guide.intro": "先安装对应平台的客户端，再连接 AI 服务。完成后可以测试本机任务，或配对另一台设备。",
  "guide.installTitle": "安装客户端",
  "guide.installBody": "按下方各平台教程选择与系统匹配的安装包。打开 AsterHand，在设置中检查所需的系统权限。",
  "guide.aiTitle": "连接 AI 服务",
  "guide.aiBody": "进入「设置 → AI 连接」。使用 ChatGPT 时，在授权页完成登录。使用兼容 API 时，填写 HTTPS 服务地址和 API Key。保存连接后打开「模型与推理」，选择可用模型并发送一条简短消息测试。",
  "guide.pairTitle": "配对接收设备",
  "guide.pairBody": "在两端开启「远程连接」，确认局域网可以互通。搜索接收端，或使用配对码、IP 地址发起申请。在接收端核对设备身份，选择「允许一次」「始终允许」或「拒绝」。",
  "guide.permissionsTitle": "设置接收端权限",
  "guide.permissionsBody": "按实际要用的工具授予屏幕、辅助功能、ADB 或 Root 权限。Android 的权限等级决定可运行的工具。iOS 的本机 AI 屏幕权限与远程屏幕权限分别管理。",
  "guide.taskTitle": "执行第一个任务",
  "guide.taskBody": "选择项目、对话和执行目标。可以先发送「列出这个项目里的文件，不修改任何内容」。核对执行设备和结果。发送点击或键盘输入之前，先查看目标屏幕。",
  "guide.troubleshoot": "若搜不到接收端，检查两端的「远程连接」和系统局域网权限。确认网络互通后，可以用配对码或接收端 IP 地址发起连接。若工具被拒绝，请先在接收端检查该项工具权限，再重试。",
};
const english = new Map();
for (const element of document.querySelectorAll('[data-i18n]')) {
  const key = element.dataset.i18n;
  if (!english.has(key)) english.set(key, element.innerHTML);
}
const videoSources = {
  en:{root:'media/AsterHand-Five-Platforms-MCP-Demo-EN-1080p.mp4?v=en-20261104',overview:'media/AsterHand-Five-Platforms-Promo-EN-1080p.mp4?v=en-20261104'},
  zh:{root:'media/AsterHand-Five-Platforms-MCP-Demo-ZH-1080p.mp4',overview:'media/AsterHand-Five-Platforms-Promo-ZH-1080p.mp4'}
};
const header = document.querySelector('.site-header');
const menu = document.querySelector('.menu-button');
function closeMenu(){ header.classList.remove('menu-open'); menu.setAttribute('aria-expanded','false'); }
menu.addEventListener('click',()=>{
  const open=header.classList.toggle('menu-open');
  menu.setAttribute('aria-expanded',String(open));
});
for(const link of document.querySelectorAll('#site-nav a'))link.addEventListener('click',closeMenu);
document.addEventListener('keydown',event=>{if(event.key==='Escape')closeMenu();});

function setLanguage(language,updateURL=false){
  const chinese=language==='zh';
  document.documentElement.lang=chinese?'zh-CN':'en';
  document.querySelector('.platform-nav').setAttribute('aria-label',chinese?translations['nav.platforms']:'Platforms');
  for(const element of document.querySelectorAll('[data-i18n]')){
    const key=element.dataset.i18n;
    element.innerHTML=chinese?translations[key]:english.get(key);
  }
  for(const button of document.querySelectorAll('[data-language]'))button.setAttribute('aria-pressed',String(button.dataset.language===language));
  const promo = document.getElementById('product-art');
  const promoSource = `assets/five-platforms-mcp-${language}.jpg`;
  if (promo.getAttribute('src') !== promoSource) promo.setAttribute('src', promoSource);
  promo.alt = chinese ? "AsterHand 本机设备 Agent 和 MCP 支持，覆盖 Windows、macOS、Linux、iOS 与 Android" : "AsterHand local device Agent and MCP support across Windows, macOS, Linux, iOS and Android";
  document.title=chinese?'AsterHand — 跨设备 Root 控制与本机 Agent':'AsterHand — Cross-device Root control';
  document.querySelector('meta[name="description"]').content=chinese?'AsterHand 为 Android、越狱 iOS 和 Windows 提供跨设备 Root 控制、本机 Agent 与 MCP 集成。':'AsterHand brings cross-device Root control, local device agents and MCP to Android, jailbroken iOS and Windows.';
  for(const kind of ['root','overview']){
    const video=document.getElementById(kind+'-video');
    const source=video.querySelector('source');
    const requested=videoSources[language][kind];
    if(source.getAttribute('src')!==requested){video.pause();source.setAttribute('src',requested);video.load();}
    video.setAttribute('aria-label',chinese?(kind==='root'?'五平台 MCP 演示':'AsterHand 产品介绍'):(kind==='root'?'Five-platform MCP demonstration':'AsterHand product overview'));
  }
  try{localStorage.setItem('asterhand-website-language',language);}catch{}
  if(updateURL){
    const url=new URL(location.href);
    if(chinese)url.searchParams.set('lang','zh');else url.searchParams.delete('lang');
    history.replaceState(null,'',url);
  }
}
for(const button of document.querySelectorAll('[data-language]'))button.addEventListener('click',()=>setLanguage(button.dataset.language,true));
let initial='en';
try{if(localStorage.getItem('asterhand-website-language')==='zh')initial='zh';}catch{}
const requested=new URLSearchParams(location.search).get('lang');
if(requested==='zh'||requested==='en')initial=requested;
setLanguage(initial);
