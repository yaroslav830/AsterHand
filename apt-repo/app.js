'use strict';
const phrases={en:{project:'Project',installStep:'01 / INSTALL',buildsStep:'02 / BUILDS',startStep:'03 / GET STARTED',verifyStep:'04 / VERIFY',detector:'Read-only environment detector ↗',eyebrow:'ASTERHAND SOFTWARE SOURCE',headline:'One source.\nThe right build.',lede:'Cross-device Root control and local device agents, installed for your jailbreak environment.',signed:'Signed package index',platforms:'Rootful · Rootless · RootHide',addTitle:'Add AsterHand to your sources',autoNote:'Sileo and Zebra select the compatible package using your device’s dpkg architecture.',environment:'Jailbreak environment',automatic:'Automatic · recommended',copy:'Copy',copied:'Copied',cydiaNote:'The Cydia button adds the Rootful-only source.',cydiaUnavailable:'Use Sileo or Zebra for this environment.',check:'Check this device',detectNote:'Safari can report iOS, but cannot reliably identify your jailbreak. Environment matching happens inside your package manager.',buildsTitle:'Built for your bootstrap.',buildsNote:'The package ID stays the same, so existing installations can upgrade in place.',howTitle:'Add. Refresh. Install.',step1Title:'Add the source',step1:'Open the link in your package manager, or copy the source URL into its Sources screen.',step2Title:'Refresh and find AsterHand',step2:'The architecture and firmware requirements select the matching build. For older clients, use the environment-specific source.',step3Title:'Set up your own tools',step3:'Connect your AI service and enable the Root and screen capabilities you need. Pairing alone never grants permissions.',trustTitle:'Know what you install.',trustText:'The original release DEBs are preserved byte for byte. Package indices include SHA-256 digests and signed Release metadata.',keyLabel:'APT SIGNING KEY FINGERPRINT',publicKey:'Public key',release:'Release notes',trustNote:'Signature verification requires your package manager to trust this public key. Never disable verification to work around a trust error.',footer:'Cross-device Root control. Local device agents.',source:'Source & documentation ↗',minimum:'Minimum target: iOS ',download:'Download DEB ↗',variantSource:'Use this environment’s source ↗',rootful:'For traditional rootful jailbreaks. Installs in the rootful layout.',rootless:'For standard rootless bootstraps. Uses the /var/jb layout.',roothide:'For RootHide bootstraps. Uses RootHide’s relocated jailbreak root.',desktop:'Open this page on a jailbroken iPhone or iPad, or copy its source URL. No jailbreak environment is inferred from a desktop browser.',iosDetected:'iOS {version} detected. Your package manager will identify the bootstrap; Safari cannot confirm Rootful, Rootless or RootHide.',ipadDetected:'iPad detected. Add the source in your package manager to identify the bootstrap.',tooOld:'iOS {version} is below the minimum supported target (iOS 14).',notCompatible:'This build targets iOS {minimum} or later. The current browser reports iOS {version}.',loadError:'Repository metadata could not be loaded. Refresh or open the GitHub release.'},zh:{project:'主项目',installStep:'01 / 安装',buildsStep:'02 / 构建',startStep:'03 / 使用',verifyStep:'04 / 校验',detector:'只读环境检测脚本 ↗',eyebrow:'ASTERHAND 越狱软件源',headline:'一个软件源。\n匹配你的越狱环境。',lede:'跨设备 Root 控制与本机 Agent，按越狱环境安装对应版本。',signed:'已签名的软件包索引',platforms:'Rootful · Rootless · RootHide',addTitle:'将 AsterHand 添加到软件源',autoNote:'Sileo、Zebra 根据设备的 dpkg 架构，自动选择兼容的软件包。',environment:'越狱环境',automatic:'自动匹配 · 推荐',copy:'复制',copied:'已复制',cydiaNote:'Cydia 按钮添加仅包含 Rootful 的独立软件源。',cydiaUnavailable:'此环境请使用 Sileo 或 Zebra。',check:'检查当前设备',detectNote:'Safari 可以识别 iOS 版本，但无法可靠读取越狱环境；环境匹配由包管理器完成。',buildsTitle:'针对不同越狱环境构建。',buildsNote:'三种包使用同一个软件包标识，已有安装可在匹配环境中原位升级。',howTitle:'添加、刷新、安装。',step1Title:'添加软件源',step1:'使用包管理器按钮，或复制地址到包管理器的“软件源”页面。',step2Title:'刷新并搜索 AsterHand',step2:'包架构和系统依赖决定兼容版本。旧版客户端可使用各环境的独立源地址。',step3Title:'配置自己的工具',step3:'连接自己的 AI 服务，并按需启用 Root 和屏幕能力。配对本身不会授予权限。',trustTitle:'清楚你安装的内容。',trustText:'保留原始 Release DEB 的完整字节；软件包索引提供 SHA-256 摘要和已签名的 Release 元数据。',keyLabel:'APT 软件源签名公钥指纹',publicKey:'签名公钥',release:'发行说明',trustNote:'校验签名需要包管理器信任此公钥。请勿通过关闭校验来绕过信任错误。',footer:'跨设备 Root 控制，本机 Agent 协同。',source:'源码与文档 ↗',minimum:'最低目标：iOS ',download:'下载 DEB ↗',variantSource:'使用此环境的软件源 ↗',rootful:'面向传统 Rootful 越狱，使用有根环境的安装布局。',rootless:'面向标准 Rootless 引导环境，安装到 /var/jb。',roothide:'面向 RootHide 引导环境，使用其重定位的越狱根目录。',desktop:'请在已越狱的 iPhone 或 iPad 打开本页，或复制软件源地址。不会根据电脑浏览器猜测越狱环境。',iosDetected:'识别到 iOS {version}。包管理器将检测引导环境；Safari 无法确认 Rootful、Rootless 或 RootHide。',ipadDetected:'识别到 iPad。请在包管理器中添加源，以识别实际引导环境。',tooOld:'iOS {version} 低于当前最低支持目标（iOS 14）。',notCompatible:'此包最低目标为 iOS {minimum}，当前浏览器报告 iOS {version}。',loadError:'无法加载软件源信息，请刷新页面或前往 GitHub Release。'}};
Object.assign(phrases.en, {
  autoNote:'Select your environment to include OpenSSH and its dependencies. The unified source contains AsterHand only and uses your existing bootstrap sources for dependencies.',
  automatic:'Automatic · AsterHand only',
  step1:'Choose the environment matching dpkg --print-architecture. Open its source in Sileo or Zebra, or copy the URL into Sources. Cydia supports the Rootful source.',
  step2:'Refresh, search for AsterHand, tap Get / Install and review the dependency queue. OpenSSH and its runtime dependencies are included in each environment-specific source.',
  updatesTitle:'Dependencies included. Updates tracked.',
  updatesText:'Environment-specific sources include original OpenSSH packages and their runtime dependencies. A scheduled workflow checks stable AsterHand GitHub Releases and the native upstream repositories every 6 hours.',
  rootfulBootstrap:"Rootful packages use Bingner / Elucubratus. Procursus rootful users should keep their bootstrap's OpenSSH and use the unified AsterHand-only source.",
  updateDevice:'Refresh your package manager and approve an upgrade to update your device. Adding a source alone installs nothing. Installing OpenSSH may start its SSH service; configure your credentials or SSH keys.',
  provenance:'Package provenance & versions ↗', thirdParty:'Third-party notices & source links ↗',
  sshPackages:'OpenSSH {version} · {count} packages with dependencies'
});
Object.assign(phrases.zh, {
  autoNote:'选择越狱环境可同时获得 OpenSSH 和依赖。统一源仅提供 AsterHand，依赖由现有引导源提供。',
  automatic:'自动匹配 · 仅 AsterHand',
  step1:'根据 dpkg --print-architecture 选择匹配环境，在 Sileo、Zebra 中打开对应源，或复制到“软件源”。Cydia 使用 Rootful 源。',
  step2:'刷新软件源，搜索 AsterHand，点击获取／安装并检查依赖队列。各环境独立源已包含 OpenSSH 及其运行依赖。',
  updatesTitle:'包含所需依赖，持续同步更新。',
  updatesText:'各环境独立源收录上游原始 OpenSSH 软件包及运行依赖。定时任务每 6 小时检查 AsterHand 的 GitHub 正式 Release 和对应环境的上游软件源。',
  rootfulBootstrap:'Rootful 包来自 Bingner／Elucubratus。Procursus Rootful 用户请保留引导自带的 OpenSSH，并使用仅提供 AsterHand 的统一源。',
  updateDevice:'设备端需刷新包管理器并确认升级。添加源本身不会安装软件；安装 OpenSSH 后，上游包可能启动 SSH 服务，请配置登录凭据或 SSH 密钥。',
  provenance:'软件包来源与版本 ↗', thirdParty:'第三方声明与源码链接 ↗',
  sshPackages:'OpenSSH {version} · 含依赖共 {count} 个包'
});
let language=localStorage.getItem('asterhand-repo-language')==='zh'?'zh':'en';
let manifest=null;
const environment=document.getElementById('environment');
const parameters=new URLSearchParams(location.search);
if(['rootful','rootless','roothide'].includes(parameters.get('environment')))environment.value=parameters.get('environment');
function t(key,values={}){let text=phrases[language][key]||key;for(const key of Object.keys(values))text=text.replace('{'+key+'}',values[key]);return text;}
function browserDevice(){const match=navigator.userAgent.match(/(?:CPU(?: iPhone)? OS|iPhone OS) (\d+)[_.](\d+)/);return{version:match?match[1]+'.'+match[2]:null,major:match?Number(match[1]):null,ipad:/iPad/.test(navigator.userAgent)||(navigator.platform==='MacIntel'&&navigator.maxTouchPoints>1)};}
function baseURL(){return manifest?manifest.base_url:new URL('./',location.href).href;}
function updateLinks(){const selected=environment.value,base=baseURL(),url=base+(selected==='auto'?'':selected+'/');document.getElementById('source-url').value=url;document.getElementById('sileo').href='sileo://source/'+url;document.getElementById('zebra').href='zbra://sources/add/'+url;const cydia=document.getElementById('cydia');const unavailable=!['auto','rootful'].includes(selected);cydia.setAttribute('aria-disabled',String(unavailable));if(unavailable)cydia.removeAttribute('href');else cydia.href='cydia://url/https://cydia.saurik.com/api/share#?source='+encodeURIComponent(base+'rootful/');document.getElementById('cydia-note').textContent=t(unavailable?'cydiaUnavailable':'cydiaNote');for(const card of document.querySelectorAll('.build'))card.classList.toggle('is-selected',card.dataset.environment===selected);}
function renderBuilds(){
  if(!manifest)return;
  document.getElementById('release-badge').textContent=manifest.version+(manifest.build?' · build '+manifest.build:'');
  document.getElementById('release-notes').href=manifest.release?manifest.release.url:'https://github.com/yaroslav830/AsterHand/releases/latest';
  const host=document.getElementById('builds');host.textContent='';
  manifest.variants.forEach((variant,index)=>{
    const card=document.createElement('article');card.className='build';card.dataset.environment=variant.environment;
    const number=document.createElement('span');number.className='number';number.textContent='0'+(index+1)+' / '+variant.label.toUpperCase();
    const title=document.createElement('h3');title.textContent=variant.label;
    const arch=document.createElement('span');arch.className='arch';arch.textContent=variant.architecture;
    const info=document.createElement('p');info.textContent=t(variant.environment);
    const minimum=document.createElement('span');minimum.className='minimum';minimum.textContent=t('minimum')+variant.minimum_ios+'+';
    card.append(number,title,arch,info,minimum);
    const ssh=manifest.openssh&&manifest.openssh[variant.environment];
    if(ssh){const text=document.createElement('p');text.className='tiny';text.textContent=t('sshPackages',{version:ssh.openssh_server_version,count:ssh.packages});card.append(text);}
    const add=document.createElement('a');add.href='?environment='+variant.environment;add.textContent=t('variantSource');
    add.addEventListener('click',event=>{event.preventDefault();environment.value=variant.environment;updateLinks();document.getElementById('install-title').scrollIntoView({behavior:'smooth',block:'center'});});
    const download=document.createElement('a');download.href='pool/'+variant.filename;download.textContent=t('download');
    card.append(add,download);host.append(card);
  });updateLinks();
}
function setLanguage(value){language=value;document.documentElement.lang=value==='zh'?'zh-CN':'en';localStorage.setItem('asterhand-repo-language',value);for(const element of document.querySelectorAll('[data-i18n]'))element.textContent=t(element.dataset.i18n);for(const button of document.querySelectorAll('[data-lang]'))button.setAttribute('aria-pressed',String(button.dataset.lang===value));renderBuilds();updateLinks();}
for(const button of document.querySelectorAll('[data-lang]'))button.addEventListener('click',()=>setLanguage(button.dataset.lang));
environment.addEventListener('change',updateLinks);
document.getElementById('check').addEventListener('click',()=>{const device=browserDevice();let result;if(device.version)result=t(device.major<14?'tooOld':'iosDetected',{version:device.version});else result=t(device.ipad?'ipadDetected':'desktop');const chosen=manifest&&manifest.variants.find(v=>v.environment===environment.value);if(chosen&&device.major&&device.major<Number(chosen.minimum_ios))result=t('notCompatible',{minimum:chosen.minimum_ios,version:device.version});document.getElementById('device-result').textContent=result;});
document.getElementById('copy').addEventListener('click',async()=>{const input=document.getElementById('source-url');try{if(navigator.clipboard&&window.isSecureContext)await navigator.clipboard.writeText(input.value);else{input.select();if(!document.execCommand('copy'))throw Error('copy failed');}document.getElementById('copy').textContent=t('copied');setTimeout(()=>document.getElementById('copy').textContent=t('copy'),1800);}catch{input.focus();input.select();}});
setLanguage(language);
fetch('repository.json',{cache:'no-cache'}).then(response=>{if(!response.ok)throw Error('metadata unavailable');return response.json();}).then(value=>{manifest=value;document.getElementById('fingerprint').textContent=value.signing_fingerprint.match(/.{1,4}/g).join(' ');renderBuilds();}).catch(()=>document.getElementById('fingerprint').textContent=t('loadError'));
