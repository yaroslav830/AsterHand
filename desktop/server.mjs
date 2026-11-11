import http from 'node:http';
import tls from 'node:tls';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import net from 'node:net';
import os from 'node:os';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {fileURLToPath} from 'node:url';
import WebSocket, {WebSocketServer} from 'ws';
import {ControlHub} from './control-core.mjs';
import {ControlAgent} from './control-agent.mjs';
import {MacWorkspace} from './control-workspace.mjs';
import {runMacHelper} from './macos-control.mjs';

const root = path.dirname(fileURLToPath(import.meta.url));
const release=JSON.parse(fs.readFileSync(path.join(root,'../version.json'),'utf8'));
const execFileAsync = promisify(execFile);
const dataRoot=path.resolve(process.env.ASTERHAND_DATA_DIR||process.env.ASTERHAND_HOME||process.env.AGENTGO_HOME||(process.platform==='darwin'?path.join(os.homedir(),'Library','Application Support','AsterHand'):path.join(root,'..')));
const privateDir=path.join(dataRoot,'.private','remote');
function shellCommand(...values){return values.map(value=>"'"+String(value).replaceAll("'","'\\''")+"'").join(' ');}
function portSetting(name,fallback){const value=process.env[name]===undefined?fallback:Number(process.env[name]);if(!Number.isInteger(value)||value<0||value>65535)throw Error('Invalid '+name);return value;}
const endpointFiles=new Set([path.join(privateDir,'desktop-session.json')]);
if(process.env.ASTERHAND_ENDPOINT_FILE){if(!path.isAbsolute(process.env.ASTERHAND_ENDPOINT_FILE))throw Error('Endpoint path must be absolute');endpointFiles.add(process.env.ASTERHAND_ENDPOINT_FILE);}
fs.mkdirSync(privateDir,{recursive:true,mode:0o700});
let config;try{config=JSON.parse(fs.readFileSync(path.join(privateDir,'desktop.json'),'utf8'));}catch{config={host:'',port:5907};}
const control=new ControlHub(path.join(dataRoot,'.private','control'),{port:portSetting('ASTERHAND_CONTROL_PORT',18769)});
const agent=new ControlAgent(control);
const workspace=process.platform==='darwin'||process.env.ASTERHAND_MAC_UI==='1'?new MacWorkspace(path.join(dataRoot,'.private','workspace'),control,agent):null;
const aiConnection={enabled:false,key:'',base:'https://api.openai.com/v1',model:'',effort:'auto',autoApprove:false};
const vncSessions=new Map();
const discoveredDevices=new Map();
async function discoverAsterHand(){
  const devices=new Map(),targets=new Set();for(const range of lanRanges()){
    for(const peer of control.state.peers||[]){if(net.isIP(peer.host)===4&&((ipv4Number(peer.host)&(0xffffffff^range.size))>>>0)===(range.network>>>0))targets.add(peer.host);}
    for(let n=1;n<range.size;n++){const host=numberIPv4((range.network+n)>>>0);if(host!==range.address)targets.add(host);}
  }
  const hosts=[...targets];let next=0;await Promise.all(Array.from({length:Math.min(48,hosts.length)},async()=>{while(next<hosts.length){const host=hosts[next++];if(!await probePort(host,18769,800))continue;try{const info=await deviceAt(host,18769);devices.set(info.device_id||host,info);if(info.pairing===2)discoveredDevices.set(info.device_id,info);}catch{}}}));return {devices:[...devices.values()]};
}
async function deviceAt(host,port){
  if(!net.isIP(host)||!Number.isInteger(port)||port<1||port>65535)throw Error('请输入有效的 IP 和端口');
  const authority=net.isIP(host)===6?'['+host+']':host;
  const response=await fetch(`http://${authority}:${port}/info`,{signal:AbortSignal.timeout(2000),redirect:'error'});if(!response.ok)throw Error('设备未响应');const info=await response.json();if(info.agentgo!==1)throw Error('不是 AsterHand 设备');return {host,port,name:String(info.name).slice(0,80),device_id:info.device_id,public_key:info.public_key,pairing:info.pairing,pair_code:info.pair_code,available:info.available,platform:info.platform};
}
async function resolveVNC(id){
  const peer=control.state.peers.find(p=>p.id===id&&p.host);if(!peer)throw Error('请选择已配对手机');
  const identity=await control.request(id,'info',{});if(identity.error||identity.platform!=='ios'||identity.screen===false)throw Error('目标未允许兼容手机远控');
  let settings=await control.request(id,'vnc.info',{});
  if(settings.error){if(settings.error!=='未知控制方法'||!config.certificate||!config.fingerprint||!config.password)throw Error(settings.error);settings=config;}
  if(!/^[a-f0-9]{64}$/.test(settings.fingerprint)||typeof settings.certificate!=='string'||settings.certificate.length>32768||typeof settings.password!=='string')throw Error('远控证书配置无效');
  const port=settings.port||5907;if(!Number.isInteger(port)||port<1||port>65535)throw Error('远控端口无效');const value={host:peer.host,port,certificate:settings.certificate,fingerprint:settings.fingerprint,password:settings.password,created:Date.now()};vncSessions.set(id,value);return value;
}
const token = crypto.randomBytes(24).toString('hex');
const prefix = `/session/${token}`;
const wss = new WebSocketServer({noServer: true, maxPayload: 1024 * 1024, perMessageDeflate: false});
let origin, browserClient;
const rootedDevices = new Set();
const types = {'.html':'text/html; charset=utf-8', '.js':'text/javascript', '.css':'text/css', '.svg':'image/svg+xml', '.png':'image/png', '.json':'application/json'};
async function adb(args, options={}) {
  return execFileAsync('adb', args, {windowsHide:true, timeout:options.timeout ?? 8000,
    maxBuffer:options.maxBuffer ?? 8*1024*1024, encoding:options.binary ? 'buffer' : 'utf8'});
}
function parseADBDevices(output) {
  return output.split(/\r?\n/).slice(1).map(line => {
    const match = line.trim().match(/^(\S+)\s+(device|unauthorized|offline)(?:\s+(.*))?$/);
    return match ? {serial:match[1], state:match[2], details:match[3] || ''} : null;
  }).filter(Boolean);
}
function addressOK(value) {
  return typeof value === 'string' && value.length <= 253 && /^[a-zA-Z0-9.:-]+$/.test(value) &&
    /^(?:\[[0-9a-fA-F:]+\]|[a-zA-Z0-9.-]+):\d{1,5}$/.test(value) && Number(value.slice(value.lastIndexOf(':')+1)) <= 65535 && Number(value.slice(value.lastIndexOf(':')+1)) > 0;
}
async function authorizedDevice(serial) {
  if (typeof serial !== 'string' || serial.length > 128) return false;
  const {stdout} = await adb(['devices','-l']);
  return parseADBDevices(stdout).some(item => item.serial === serial && item.state === 'device');
}
async function discoverDevices() {
  const result = {devices:[], adbAvailable:true, adbMessage:''};
  const known = new Set();
  try {
    const [{stdout:deviceText}, mdnsResult] = await Promise.all([
      adb(['devices','-l']), adb(['mdns','services'],{timeout:5000}).catch(error => ({stdout:''}))
    ]);
    for (const device of parseADBDevices(deviceText)) {
      if (device.state !== 'device') continue;
      known.add(device.serial);
      result.devices.push({kind:'android',serial:device.serial,name:(device.details.match(/model:([^\s]+)/)?.[1] || device.serial).replaceAll('_',' '),state:'已授权',rooted:false});
    }
    const serviceRows = (mdnsResult.stdout || '').split(/\r?\n/);
    for (const row of serviceRows) {
      if (!row.includes('_adb-tls-connect._tcp')) continue;
      const endpoint = row.match(/(?:\[[0-9a-fA-F:]+\]|[0-9.]+|[a-zA-Z0-9.-]+):\d{1,5}/)?.[0];
      if (!endpoint || !addressOK(endpoint) || known.has(endpoint)) continue;
      try {
        await adb(['connect',endpoint],{timeout:5000});
        const {stdout} = await adb(['devices','-l']);
        const device = parseADBDevices(stdout).find(item => item.serial === endpoint && item.state === 'device');
        if (device) {
          known.add(device.serial);
          result.devices.push({kind:'android',serial:device.serial,name:(device.details.match(/model:([^\s]+)/)?.[1] || device.serial).replaceAll('_',' '),state:'已授权',rooted:false});
        } else result.devices.push({kind:'android',serial:endpoint,name:'Android 无线调试设备',state:'待在手机上确认 ADB 授权',rooted:false});
      } catch { result.devices.push({kind:'android',serial:endpoint,name:'Android 无线调试设备',state:'已配对，等待连接',rooted:false}); }
    }
  } catch (error) {
    result.adbAvailable = false;
    result.adbMessage = error.code === 'ENOENT' ? '未找到 adb。安装 Google Android SDK Platform-Tools，并将 adb 加入 PATH。' : `ADB 搜索失败：${String(error.message || error).slice(0,240)}`;
  }
  return result;
}
function ipv4Number(value) { return value.split('.').reduce((n,part) => ((n << 8) | Number(part)) >>> 0,0); }
function numberIPv4(value) { return [24,16,8,0].map(shift => (value >>> shift) & 255).join('.'); }
function isPrivateIPv4(value) {
  const [a,b]=value.split('.').map(Number);
  return a===10 || (a===172&&b>=16&&b<=31) || (a===192&&b===168);
}
function lanRanges() {
  const ranges = [];
  for (const entries of Object.values(os.networkInterfaces())) for (const item of entries || []) {
    if (item.family !== 'IPv4' || item.internal || !item.netmask || !isPrivateIPv4(item.address)) continue;
    const mask = ipv4Number(item.netmask), size = (0xffffffff ^ mask) >>> 0;
    if (size > 4095 || size < 2) continue;
    const network = ipv4Number(item.address) & mask;
    ranges.push({network,size,address:item.address});
  }
  return ranges;
}
function probePort(host, port, timeout=500) {
  return new Promise(resolve => {
    const socket = net.createConnection({host,port}); let done=false;
    const finish = value => {if(done)return;done=true;socket.destroy();resolve(value);};
    socket.setTimeout(timeout); socket.once('connect',()=>finish(true)); socket.once('timeout',()=>finish(false)); socket.once('error',()=>finish(false));
  });
}
async function discoverPocketPhones() {
  const found = new Set([config.host]);
  const ranges = lanRanges();
  for (const range of ranges) {
    if (range.size > 256) continue;
    const candidates = Array.from({length:range.size-1},(_,i)=>numberIPv4((range.network + i + 1) >>> 0)).filter(ip => ip !== range.address && ip !== '255.255.255.255');
    let next=0;
    const workers = Array.from({length:Math.min(32,candidates.length)},async()=>{while(next<candidates.length){const ip=candidates[next++];if(await probePort(ip,config.port))found.add(ip);}});
    await Promise.all(workers);
  }
  return [...found].slice(0,32).map(host => ({kind:'iphone',serial:host,name:host===config.host?'已配对 iPhone':'发现 AsterHand iPhone',state:host===config.host?'已配对':'需单独配对',paired:host===config.host}));
}
async function requestBody(req, limit=65536) {
  const chunks=[]; let size=0;
  for await (const chunk of req) {size+=chunk.length;if(size>limit)throw new Error('Request body too large');chunks.push(chunk);}
  return JSON.parse(Buffer.concat(chunks).toString('utf8'));
}
const server = http.createServer((req, res) => {
  // Older WebKit does not include ws: in an http: page's CSP 'self'. Use only
  // this listener's exact loopback origin, never the request's Host header.
  const finish = (code, content, type='text/plain') => {res.writeHead(code, {'Content-Type':type, 'Cache-Control':'no-store', 'X-Content-Type-Options':'nosniff', 'Referrer-Policy':'no-referrer', 'Content-Security-Policy':`default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self' ${origin.replace(/^http:/,'ws:')}; img-src 'self' data: blob:; frame-src 'self'; frame-ancestors 'self'`});res.end(content);};
  if (`http://${req.headers.host}` !== origin || (req.headers.origin && req.headers.origin !== origin)) return finish(403, 'Forbidden');
  const url = new URL(req.url, origin);
  if (!url.pathname.startsWith(prefix + '/')) return finish(404, 'Not found');
  let name;
  try {name = decodeURIComponent(url.pathname.slice(prefix.length));}
  catch {return finish(400,'Invalid path');}
  if (name.startsWith('/control/')) {
    const run=async()=>{
      if(req.method==='GET'&&name==='/control/state'){await control.permissions();if(workspace)await workspace.auth.ready;return {...control.info(),release,agent:agent.view(),ai:workspace?{...workspace.auth.view(),enabled:workspace.auth.config.enabled!==false}:{enabled:aiConnection.enabled,configured:!!aiConnection.key,model:aiConnection.model},selectedDeviceName:control.state.name};}
      if(req.method==='GET'&&name==='/control/permissions/status')return control.permissions(true);
      if(name.startsWith('/control/mac/')){if(!workspace)throw Error('Mac workspace is unavailable on this platform');if(req.method==='POST'&&req.headers.origin!==origin)throw Error('Forbidden');const payload=req.method==='POST'?await requestBody(req,16*1024*1024):undefined;const value=await workspace.route(name.slice('/control/mac/'.length),req.method,payload);if(name==='/control/mac/state'){value.permissions=await control.permissions();value.platform=process.platform;}return value;}
      if(req.method==='GET'&&name==='/control/codex/status'){if(workspace){await workspace.auth.ready;return {platform:process.platform,enabled:workspace.auth.config.enabled!==false,configured:workspace.auth.view().configured,agent:agent.view()};}return {enabled:aiConnection.enabled,configured:!!aiConnection.key,agent:agent.view()};}
      if(req.method==='GET'&&name==='/control/mcp-guide'){
        const project=path.resolve(root,'..'),entry=path.join(project,'mcp','server.mjs');let configured=false;
        try{const record=JSON.parse(fs.readFileSync(path.join(dataRoot,'.private','mcp','installation.json'),'utf8')),text=fs.readFileSync(record.configuration,'utf8');configured=path.resolve(record.server)===entry&&text.includes('[mcp_servers.asterhand]')&&text.includes(JSON.stringify(entry).slice(1,-1));}catch{}
        const ready=fs.existsSync(path.join(project,'mcp','node_modules','@modelcontextprotocol','sdk','package.json'));
        return {configured,dependencies_ready:ready,command:process.platform==='darwin'?shellCommand(process.execPath,fs.existsSync(path.join(project,'scripts','install_macos_mcp.mjs'))?path.join(project,'scripts','install_macos_mcp.mjs'):path.join(root,'macos','install-mcp.mjs')):`python "${path.join(project,'scripts','install_asterhand_mcp.py')}"`,name:'asterhand',version:release.version,tools:22,example:'使用 AsterHand MCP 列出已配对设备，先截图确认，再完成我的操作。'};
      }
      if(req.method==='GET'&&name==='/control/skill-guide'){
        const codex=process.env.CODEX_HOME||path.join(os.homedir(),'.codex'),project=path.resolve(root,'..');
        const skill=path.join(codex,'skills','asterhand-skill'),installer=path.join(project,'scripts','install_asterhand_skill.ps1');
        let configured=false;for(const filename of ['asterhand.json','agentgo.json'])try{configured=path.resolve(JSON.parse(fs.readFileSync(path.join(codex,filename),'utf8').replace(/^\uFEFF/,'')).project)===project;if(configured)break;}catch{}
        return {installed:fs.existsSync(path.join(skill,'SKILL.md')),configured,command:process.platform==='darwin'?shellCommand(process.execPath,fs.existsSync(path.join(project,'scripts','install_macos_skill.mjs'))?path.join(project,'scripts','install_macos_skill.mjs'):path.join(root,'macos','install-skill.mjs')):`powershell -NoProfile -ExecutionPolicy Bypass -File "${installer}"`,skill,example:'使用 $asterhand-skill 列出已配对设备，连接我的 iPhone，先截图确认屏幕。'};
      }
      if(req.method!=='POST'||req.headers.origin!==origin)throw Error('Forbidden');
      const body=await requestBody(req);
      if(name==='/control/permissions/request'){if(process.platform!=='darwin')throw Error('Mac permissions are unavailable on this platform');if(!['screen_recording','accessibility'].includes(body.permission))throw Error('Invalid permission');const result=await runMacHelper({tool:'permissions_request',permission:body.permission});control.permissionState=null;return {...result,request_pending:true};}
      if(name==='/control/presence'){control.uiActive=body.active===true;control.uiUpdated=Date.now();return {};}
      if(name==='/control/background'){control.state.background=body.enabled===true;control.save();return control.info();}
      if(name==='/control/pair-code'){if(typeof body.fixed!=='boolean'||(body.code&&!/^\d{6}$/.test(body.code)))throw Error('自定义配对码需要 6 位数字');control.state.pair_code_fixed=body.code||control.pairing.info().pair_code;control.state.pair_code_mode=body.fixed?'fixed':'rotating';control.pairing.codeExpires=0;control.save();return control.info();}
      if(name==='/control/ai/connection'){if(workspace){workspace.idle();await workspace.auth.settings(body);if(body.enabled===false)agent.stop();return {enabled:workspace.auth.config.enabled!==false,configured:workspace.auth.view().configured};}if(typeof body.key==='string'&&body.key)aiConnection.key=body.key;if(typeof body.base==='string')aiConnection.base=body.base;if(typeof body.model==='string')aiConnection.model=body.model;if(typeof body.effort==='string')aiConnection.effort=body.effort;if(typeof body.autoApprove==='boolean')aiConnection.autoApprove=body.autoApprove;if(typeof body.enabled==='boolean')aiConnection.enabled=body.enabled;if(!aiConnection.enabled)agent.stop();return {enabled:aiConnection.enabled,configured:!!aiConnection.key};}
      if(name==='/control/codex/message'){if(workspace){if(typeof body.target!=='string')throw Error('Specify an exact target device');if(agent.job?.running){if(body.target!==agent.job.target)throw Error('Target does not match the running task');return agent.receive(body.message);}await workspace.send({...body,chat:workspace.state.currentChat});return agent.view();}if(!aiConnection.enabled)throw Error('请先在控制中心开启 AI 连接');if(!aiConnection.key||!aiConnection.model)throw Error('请先在设置里配置 AI');if(agent.job?.running){if(body.target!==agent.job.target)throw Error('目标与运行中的 AI 任务不一致');return agent.receive(body.message);}if(typeof body.target!=='string')throw Error('请明确指定目标设备');return agent.start({...aiConnection,target:body.target,message:body.message});}
      if(name==='/control/name'){if(typeof body.name!=='string'||!body.name.trim()||body.name.length>80)throw Error('名称为 1–80 个字符');control.state.name=body.name.trim();control.save();return control.info();}
      if(name==='/control/connect/ip')return control.pairing.begin(await deviceAt(body.host,body.port||18769));
      if(name==='/control/connect/code'){if(!/^\d{6}$/.test(body.code))throw Error('请输入 6 位配对码');const scan=await discoverAsterHand();const matches=scan.devices.filter(d=>d.pair_code===body.code);if(matches.length!==1)throw Error(matches.length?'多个设备使用相同配对码，请搜索后按设备标识选择':'未找到此配对码，请检查同一局域网及配对码是否过期');return control.pairing.begin(matches[0]);}
      if(name==='/control/pair/request'){const remote=discoveredDevices.get(body.device_id);if(!remote)throw Error('请先搜索设备');return control.pairing.begin(remote);}
      if(name==='/control/pair/status')return control.pairing.poll(body.id);
      if(name==='/control/pair/decision')return control.pairing.decide(body.id,body.mode);
      if(name==='/control/trust')return control.pairing.setTrust(body.device_id,body.mode);
      if(name==='/control/disconnect'){const peer=control.state.peers.find(p=>p.id===body.target);if(peer){try{await control.request(peer.id,'session.close',{});}finally{if(peer.mode==='once')control.revoke(peer.id);}}return {closed:true};}
      if(name==='/control/enable'){control.state.enabled=body.enabled===true;if(!control.state.enabled)for(const [id,t]of control.terminals)if(t.owner!=='local')control.closeTerminal(id);control.save();return control.info();}
      if(name==='/control/invite')return {invitation:control.createInvite(body.host)};
      if(name==='/control/import')return control.importInvite(body.invitation);
      if(name==='/control/revoke'){control.revoke(body.id);return control.info();}
      if(name==='/control/call')return body.target==='local'?control.execute(body.method,body.args,'local'):control.request(body.target,body.method,body.args);
      if(name==='/control/vnc'){const info=await resolveVNC(body.target);return {password:info.password,websocket:origin.replace('http:','ws:')+prefix+'/control/vnc/'+body.target};}
      if(name==='/control/agent/start'){if(workspace){await workspace.send({...body,message:body.message,chat:workspace.state.currentChat});return agent.view();}if(!aiConnection.enabled)throw Error('请先开启 AI 连接');return agent.start({...aiConnection,...body,key:body.key||aiConnection.key});}
      if(name==='/control/agent/stop'){if(body.job&&body.job!==agent.job?.id)throw Error('AI 任务标识已变化');if(workspace)workspace.stopCurrent();else agent.stop();return {};}
      if(name==='/control/agent/approve'){agent.approve(body.id,body.allow);return {};}
      if(name==='/control/discover')return discoverAsterHand();
      throw Error('Unknown control route');
    };run().then(value=>finish(200,JSON.stringify(value),'application/json')).catch(e=>finish(400,JSON.stringify({error:e.message}),'application/json'));return;
  }
  if (name === '/bootstrap' && req.method === 'GET') return finish(200, JSON.stringify({host: config.host, password:config.password, websocket:`ws://${req.headers.host}${prefix}/rfb`}), 'application/json');
  if (name === '/devices/search' && req.method === 'GET') {
    Promise.all([discoverPocketPhones(),discoverDevices()]).then(([phones,android])=>finish(200,JSON.stringify({...android,devices:[...phones,...android.devices]}),'application/json')).catch(()=>finish(500,'{"error":"搜索设备失败"}','application/json'));
    return;
  }
  if (name === '/android/pair' && req.method === 'POST') {
    if (req.headers.origin !== origin) return finish(403,'Forbidden');
    requestBody(req).then(async body=>{
      const address=body.address, code=body.code;
      if (!addressOK(address) || !/^\d{6}$/.test(code || '')) return finish(400,JSON.stringify({error:'请输入 Android 无线调试配对地址和 6 位配对码。'}),'application/json');
      const {stdout}=await adb(['pair',address,code],{timeout:15000});finish(200,JSON.stringify({message:stdout.trim()}),'application/json');
    }).catch(error=>finish(400,JSON.stringify({error:String(error.message||error).slice(0,240)}),'application/json'));
    return;
  }
  if (name === '/android/connect' && req.method === 'POST') {
    if (req.headers.origin !== origin) return finish(403,'Forbidden');
    requestBody(req).then(async body=>{
      let endpoint=body.address, device=null;
      if(typeof body.serial==='string'&&body.serial.length<=128) {
        if(!await authorizedDevice(body.serial))return finish(403,JSON.stringify({error:'Android 设备未授权或已断开。'}),'application/json');
        const {stdout:list}=await adb(['devices','-l']); device=parseADBDevices(list).find(item=>item.serial===body.serial&&item.state==='device');
      } else {
        if (!addressOK(endpoint)) return finish(400,JSON.stringify({error:'设备地址格式无效。'}),'application/json');
        const {stdout}=await adb(['connect',endpoint],{timeout:8000});
        const {stdout:list}=await adb(['devices','-l']);
        device=parseADBDevices(list).find(item=>item.serial===endpoint&&item.state==='device');
        if (!device) return finish(409,JSON.stringify({error:stdout.trim()||'设备未授权，请在 Android 屏幕上确认 ADB 提示。'}),'application/json');
      }
      if (!device) return finish(409,JSON.stringify({error:'设备未授权，请在 Android 屏幕上确认 ADB 提示。'}),'application/json');
      let rooted=false; try {const rootCheck=await adb(['-s',device.serial,'shell','su','-c','id'],{timeout:3500});rooted=/uid=0\(root\)/.test(rootCheck.stdout);} catch {}
      if(rooted)rootedDevices.add(device.serial);
      finish(200,JSON.stringify({device:{serial:device.serial,name:(device.details.match(/model:([^\s]+)/)?.[1]||device.serial).replaceAll('_',' '),rooted}}),'application/json');
    }).catch(error=>finish(400,JSON.stringify({error:String(error.message||error).slice(0,240)}),'application/json'));
    return;
  }
  if (name === '/android/screen' && req.method === 'GET') {
    const serial=url.searchParams.get('serial');
    authorizedDevice(serial).then(async allowed=>{
      if (!allowed) return finish(403,'设备未授权或已断开。');
      let image;
      if(rootedDevices.has(serial)) {
        try {image=(await adb(['-s',serial,'exec-out','su','-c','/system/bin/screencap -p'],{binary:true,timeout:8000,maxBuffer:16*1024*1024})).stdout;}
        catch {image=null;}
      }
      if(!Buffer.isBuffer(image)||image.length<8||image.readUInt32BE(0)!==0x89504e47) try {image=(await adb(['-s',serial,'exec-out','screencap','-p'],{binary:true,timeout:8000,maxBuffer:16*1024*1024})).stdout;}
      catch {image=null;}
      if (!Buffer.isBuffer(image)||image.length<8||image.readUInt32BE(0)!==0x89504e47) {
        try {image=(await adb(['-s',serial,'exec-out','su','-c','/system/bin/screencap -p'],{binary:true,timeout:8000,maxBuffer:16*1024*1024})).stdout;}
        catch {return finish(500,'Root 截屏失败；请确认设备已授权 Root 管理器并安装 su。');}
      }
      finish(200,image,'image/png');
    }).catch(()=>finish(500,'Android 截屏失败。'));
    return;
  }
  if (name === '/android/input' && req.method === 'POST') {
    if (req.headers.origin !== origin) return finish(403,'Forbidden');
    requestBody(req).then(async body=>{
      const serial=body.serial;
      if (!await authorizedDevice(serial)) return finish(403,JSON.stringify({error:'Android 设备未授权或已断开。'}),'application/json');
      const n=v=>Number.isFinite(Number(v))&&Number(v)>=0&&Number(v)<=8192?String(Math.round(Number(v))):null;
      let args;
      if(body.action==='tap'&&n(body.x)&&n(body.y)) args=['-s',serial,'shell','input','tap',n(body.x),n(body.y)];
      else if(body.action==='swipe'&&[body.x1,body.y1,body.x2,body.y2].every(v=>n(v))){const duration=String(Math.max(80,Math.min(1500,Number(body.duration)||350)));args=['-s',serial,'shell','input','swipe',n(body.x1),n(body.y1),n(body.x2),n(body.y2),duration];}
      else if(body.action==='key'&&({home:3,back:4,enter:66,backspace:67,power:26}[body.key]))args=['-s',serial,'shell','input','keyevent',String({home:3,back:4,enter:66,backspace:67,power:26}[body.key])];
      else if(body.action==='text'&&typeof body.text==='string'&&body.text.length<=256&&/^[A-Za-z0-9 .,_@:+\-]+$/.test(body.text))args=['-s',serial,'shell','input','text',body.text.replace(/ /g,'%s')];
      else return finish(400,JSON.stringify({error:'操作参数无效；输入文字目前仅支持英文、数字和常用标点。'}),'application/json');
      try {await adb(args,{timeout:5000});finish(200,'{}','application/json');}catch(error){finish(500,JSON.stringify({error:String(error.message||error).slice(0,200)}),'application/json');}
    }).catch(error=>finish(400,JSON.stringify({error:String(error.message||error).slice(0,200)}),'application/json'));
    return;
  }
  if (req.method !== 'GET') return finish(405,'Method not allowed');
  const file = path.resolve(root, 'public', '.' + (name === '/' || name === '/index.html' ? '/control.html' : name));
  if (!file.startsWith(path.join(root, 'public') + path.sep)) return finish(403, 'Forbidden');
  try {finish(200, fs.readFileSync(file), types[path.extname(file)] || 'application/octet-stream');}
  catch {finish(404, 'Not found');}
});
server.on('upgrade', (req, socket, head) => {
  if (`http://${req.headers.host}`===origin&&req.headers.origin===origin&&req.url.startsWith(prefix+'/control/vnc/')) {
    const id=req.url.slice((prefix+'/control/vnc/').length),info=vncSessions.get(id);
    if(!info||Date.now()-info.created>60000||!control.state.peers.some(p=>p.id===id&&p.host===info.host)){socket.destroy();return;}
    wss.handleUpgrade(req,socket,head,local=>{
      let remote;try{remote=new WebSocket(`wss://${net.isIP(info.host)===6?'['+info.host+']':info.host}:${info.port}/websockify`,['binary'],{ca:info.certificate,servername:'pocketcodex.local',rejectUnauthorized:true,origin,perMessageDeflate:false,handshakeTimeout:10000,maxPayload:16*1024*1024,checkServerIdentity(host,cert){const error=tls.checkServerIdentity(host,cert);if(error)return error;if(crypto.createHash('sha256').update(cert.raw).digest('hex')!==info.fingerprint)return Error('Device certificate mismatch');}});}catch{local.close();return;}
      let ended=false,busy=false;const queue=[];let queued=0;
      const end=()=>{if(ended)return;ended=true;clearInterval(watch);local.close();remote.close();};
      const watch=setInterval(async()=>{if(busy||ended)return;busy=true;try{if(!control.state.peers.some(p=>p.id===id))return end();const r=await control.request(id,'info',{});if(r.error||r.screen===false)end();}catch{end();}finally{busy=false;}},2000);
      let lastManual=0;
      local.on('message',(data,binary)=>{if(!binary||data.length>1024*1024)return end();if(((data.length===6&&data[0]===5)||(data.length===8&&data[0]===4))&&Date.now()-lastManual>400){lastManual=Date.now();control.request(id,'presence',{actor:'manual',active:true}).catch(()=>{});}if(remote.readyState===WebSocket.OPEN){if(remote.bufferedAmount>1024*1024)return end();remote.send(data,{binary:true});}else if(remote.readyState===WebSocket.CONNECTING&&queued+data.length<=1024*1024){queue.push(data);queued+=data.length;}else end();});
      remote.on('open',()=>{for(const data of queue)remote.send(data,{binary:true});queue.length=0;});remote.on('message',data=>{if(local.readyState===WebSocket.OPEN){if(local.bufferedAmount>8*1024*1024)return end();local.send(data,{binary:true});}});
      remote.on('close',end);remote.on('error',end);local.on('close',end);local.on('error',end);
    });return;
  }
  if (`http://${req.headers.host}`===origin&&req.headers.origin===origin&&req.url.startsWith(prefix+'/control/stream/')) {
    const target=req.url.slice((prefix+'/control/stream/').length);
    if(target!=='local'&&!control.state.peers.some(p=>p.id===target&&p.host)){socket.destroy();return;}
    wss.handleUpgrade(req,socket,head,local=>{const abort=new AbortController();let closed=false;
      const end=()=>{if(closed)return;closed=true;abort.abort();local.close();};
      try{control.stream(target,frame=>{if(local.readyState===WebSocket.OPEN&&local.bufferedAmount<512*1024)local.send(frame,{binary:true});},error=>{if(local.readyState===WebSocket.OPEN)local.send(JSON.stringify({error:error.message}));end();},abort.signal);}catch(error){local.send(JSON.stringify({error:error.message}));end();}
      local.on('close',end);local.on('error',end);local.on('message',()=>end());
    });return;
  }
  if (`http://${req.headers.host}` !== origin || req.headers.origin !== origin || req.url !== prefix + '/rfb' || browserClient) {socket.destroy(); return;}
  wss.handleUpgrade(req, socket, head, local => {
    browserClient = local;
    const remote = new WebSocket(`wss://${config.host}:${config.port}/websockify`, ['binary'], {
      ca:config.certificate, servername:'pocketcodex.local', rejectUnauthorized:true, origin,
      checkServerIdentity(host, cert) {
        const error = tls.checkServerIdentity(host, cert);
        if (error) return error;
        if (crypto.createHash('sha256').update(cert.raw).digest('hex') !== config.fingerprint) return new Error('Device certificate mismatch');
      }, perMessageDeflate:false, handshakeTimeout:8000, maxPayload:16 * 1024 * 1024
    });
    const queue = []; let queued = 0;
    const end = () => {if (browserClient === local) browserClient = null; local.close(); remote.close();};
    local.on('message', (data, binary) => {
      if (!binary || data.length > 1024 * 1024) return end();
      if (remote.readyState === WebSocket.OPEN) {
        if (remote.bufferedAmount > 4 * 1024 * 1024) return end();
        remote.send(data, {binary:true});
      } else if (remote.readyState === WebSocket.CONNECTING && queued + data.length <= 1024 * 1024) {queue.push(data); queued += data.length;}
      else end();
    });
    remote.on('open', () => {for (const data of queue) remote.send(data, {binary:true}); queue.length = 0;});
    remote.on('message', data => {if (local.readyState === WebSocket.OPEN) {if (local.bufferedAmount > 16 * 1024 * 1024) return end(); local.send(data, {binary:true});}});
    remote.on('error', () => {console.log('Phone connection failed; check app remote switch, Wi-Fi and pairing.');end();});
    remote.on('close', end); local.on('close', end); local.on('error', end);
  });
});
server.listen(portSetting('ASTERHAND_PORT',18767), '127.0.0.1', () => {
  origin = 'http://127.0.0.1:'+server.address().port;
  const url = origin + prefix + '/';
  for(const file of endpointFiles){fs.mkdirSync(path.dirname(file),{recursive:true,mode:0o700});const temporary=file+'.'+crypto.randomUUID()+'.tmp';try{fs.writeFileSync(temporary,JSON.stringify({pid:process.pid,url}),{flag:'wx',mode:0o600});fs.renameSync(temporary,file);if(process.platform!=='win32')fs.chmodSync(file,0o600);}finally{if(fs.existsSync(temporary))fs.unlinkSync(temporary);}}
  console.log('AsterHand control center is ready on loopback port '+server.address().port+'.');
});
server.on('error', e => {console.error('Cannot start local remote panel: ' + e.code);process.exit(1);});
let stopping=false;async function shutdown(){if(stopping)return;stopping=true;const forced=setTimeout(()=>process.exit(0),5000);forced.unref();workspace?.close();agent.stop();for(const c of wss.clients)c.terminate();for(const file of endpointFiles)try{if(JSON.parse(fs.readFileSync(file,'utf8')).pid===process.pid)fs.unlinkSync(file);}catch{}server.closeAllConnections?.();await Promise.allSettled([new Promise(resolve=>server.close(resolve)),control.close()]);process.exit(0);}
process.on('SIGINT',shutdown);process.on('SIGTERM',shutdown);
if(process.env.ASTERHAND_MANAGED==='1'){process.stdin.resume();process.stdin.on('end',shutdown);}
