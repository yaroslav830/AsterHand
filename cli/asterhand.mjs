// Optional command-line adapter. Operational guidance prefers the MCP tools.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {findConfig,loadPeers,resolvePeer,request,recordStream,localControl,uploadAttachment} from '../shared/asterhand-client.mjs';
export {findConfig,loadPeers,resolvePeer,request,recordStream,localControl,uploadAttachment} from '../shared/asterhand-client.mjs';
function options(argv){
  const flags={},words=[];
  for(let i=0;i<argv.length;i++){
    const arg=argv[i];if(!arg.startsWith('--')){words.push(arg);continue;}
    const key=arg.slice(2);if(key==='help'){flags.help=true;continue;}
    if(!['config','device','out','x','y','x2','y2','duration','text','text-file','command','command-file','timeout','tool','args-file','session','offset','job','lease','seconds','host','port','id','code','name','file','project','chat','question','confirm'].includes(key))throw Error('未知选项 '+arg);
    if(i+1>=argv.length||argv[i+1].startsWith('--'))throw Error('选项缺少值 '+arg);
    flags[key]=argv[++i];
  }
  return {flags,words};
}
function textArg(flags,name){
  if(flags[name]!==undefined&&flags[name+'-file']!==undefined)throw Error('文字与文件选项不能同时指定');
  if(flags[name+'-file'])return fs.readFileSync(flags[name+'-file'],'utf8').replace(/^\uFEFF/,'');
  if(flags[name]===undefined)throw Error('缺少 --'+name+'-file 或 --'+name);return flags[name];
}
function numberArg(flags,name,low,high,fallback){
  const value=flags[name]===undefined?fallback:Number(flags[name]);
  if(!Number.isFinite(value)||value<low||value>high)throw Error('--'+name+' 必须在 '+low+'–'+high+' 范围');return value;
}
export async function main(argv){
  if(argv.length===1&&argv[0]==='--version'){const release=JSON.parse(fs.readFileSync(new URL('../version.json',import.meta.url),'utf8'));console.log('AsterHand '+release.version+' (build '+release.build+')');return;}
  const {flags:f,words}=options(argv),action=words[0];
  if(f.help||!action){console.log(`AsterHand Codex CLI (Node 20+)
list | info | screenshot [--out NEW_PATH] | home
tap --x 0..1 --y 0..1
swipe --x N --y N --x2 N --y2 N [--duration 0.4]
type --text-file UTF8_FILE
shell --command-file UTF8_FILE [--timeout 30]
tool --tool read_file|write_file|list_directory --args-file JSON_FILE
terminal open|read|write|interrupt|close [--session ID] [--offset N] [--text-file UTF8_FILE]
disconnect | control begin [--lease 120] | control end
ai status|read [--job JOB_ID] | ai send --device UUID_OR_local --text-file UTF8_FILE | ai stop
devices discover | devices pair --host IP [--port 18769] | devices poll --id REQUEST
devices code --code SIX_DIGITS
desktop state|guide|name|background|enable|pair-code|ai-connection|trust|revoke|decision --args-file JSON_FILE
app capabilities | app ACTION --args-file JSON_FILE
project list|create|select|rename|delete|export | chat list|create|select|rename|delete|read
phone-ai status|send|stop|continue|pause|answer --args-file JSON_FILE
voice status|start|stop|mute --args-file JSON_FILE
settings get|set --args-file JSON_FILE | services status|restart|stop|start|result
attachment list|add|clear | attachment upload --file FILE --project UUID --chat UUID
stream --seconds 1..60 --out NEW_FILE.mjpg
Every remote action requires --device EXACT_UUID; optional --config PATH.
Credentials are read locally, never printed. No automatic retries.`);return;}
  const extended=['devices','desktop','app','project','chat','phone-ai','voice','settings','services','attachment'];
  const commands=['list','info','screenshot','home','tap','swipe','type','shell','tool','terminal','disconnect','control','ai','stream',...extended];if(!commands.includes(action))throw Error('未知命令');
  if(words.length>(['terminal','ai','control',...extended].includes(action)?2:1))throw Error('多余的命令参数');
  const config=findConfig(f.config);
  if(action==='desktop'){
    const op=words[1],routes={state:'state',guide:'skill-guide',name:'name',background:'background',enable:'enable','pair-code':'pair-code',trust:'trust',revoke:'revoke',decision:'pair/decision','ai-connection':'ai/connection'};
    if(!Object.hasOwn(routes,op))throw Error('未知 Windows 控制中心操作');
    let body;if(!['state','guide'].includes(op)){body=f['args-file']?JSON.parse(fs.readFileSync(f['args-file'],'utf8').replace(/^\uFEFF/,'')):{};if(!body||typeof body!=='object'||Array.isArray(body))throw Error('参数必须是 JSON 对象');if(['trust','revoke','decision'].includes(op)&&f.confirm!=='true')throw Error('授权变更需要 --confirm true 和用户明确授权');}
    console.log(JSON.stringify(await localControl(config,routes[op],body),null,2));return;
  }
  if(action==='devices'){
    const op=words[1];let route,body={};if(op==='discover')route='discover';else if(op==='pair'){route='connect/ip';body={host:f.host,port:numberArg(f,'port',1,65535,18769)};}else if(op==='poll'){route='pair/status';body={id:f.id};}else if(op==='code'){route='connect/code';body={code:f.code};}else throw Error('未知发现/配对命令');console.log(JSON.stringify(await localControl(config,route,body),null,2));return;
  }
  if(action==='ai'){
    const operation=words[1];if(!['status','read','send','stop'].includes(operation))throw Error('未知 AI 操作');
    const sessionFile=path.resolve(path.dirname(config),'../..','.private/remote/desktop-session.json');
    const session=JSON.parse(fs.readFileSync(sessionFile,'utf8')),base=new URL(session.url);
    if(base.protocol!=='http:'||base.hostname!=='127.0.0.1'||!/^\/session\/[a-f0-9]{48}\/$/.test(base.pathname))throw Error('无效的本机控制中心地址');
    const route=operation==='send'?'codex/message':operation==='stop'?'agent/stop':'codex/status';let body;
    if(operation==='send'){if(!f.device)throw Error('AI 任务必须用 --device 明确指定目标设备或 local');const target=f.device==='local'?'local':loadPeers(config).find(p=>p.id===f.device||p.device_id===f.device)?.id;if(!target)throw Error('未找到已授权目标');body={message:textArg(f,'text'),target};}else if(operation==='stop'){if(!f.job)throw Error('停止 Windows AI 需要 --job');body={job:f.job};}
    const response=await fetch(new URL('control/'+route,base),{method:body?'POST':'GET',headers:body?{'Content-Type':'application/json',Origin:base.origin}:{},body:body?JSON.stringify(body):undefined,signal:AbortSignal.timeout(15000),redirect:'error'});
    const result=await response.json();if(!response.ok||result.error)throw Error(result.error||'控制中心拒绝 AI 通信');
    if(f.job&&operation!=='stop'&&result.agent?.id!==f.job)throw Error('AI 当前任务与指定的 --job 不一致');
    if(operation==='read')console.log(JSON.stringify({enabled:result.enabled,job:result.agent?.id,running:result.agent?.running,pending:result.agent?.pending,events:result.agent?.events?.slice(numberArg(f,'offset',0,120,0))},null,2));else console.log(JSON.stringify(result,null,2));return;
  }
  const peers=loadPeers(config);
  if(action==='list'){console.log(JSON.stringify({devices:peers.map(({id,name,host,port,device_id,mode})=>({id,name,host,port,device_id,mode}))},null,2));return;}
  if(!f.device)throw Error('必须用 --device 指定已配对设备 UUID');
  const peer=resolvePeer(config,f.device);
  if(action==='stream'){if(!f.out)throw Error('需要新的 --out MJPEG 文件');console.log(JSON.stringify(await recordStream(peer,path.resolve(f.out),numberArg(f,'seconds',1,60,10)),null,2));return;}
  if(extended.includes(action)){
    let args=f['args-file']?JSON.parse(fs.readFileSync(f['args-file'],'utf8').replace(/^\uFEFF/,'')):{};if(!args||typeof args!=='object'||Array.isArray(args))throw Error('参数必须是 JSON 对象');
    if(action==='attachment'&&words[1]==='upload'){
      if(!f.file||!f.project||!f.chat)throw Error('上传需要 --file --project --chat');const result=await uploadAttachment({file:f.file,project:f.project,chat:f.chat,call:(action,args)=>request(resolvePeer(config,f.device),'app',{...args,action})});console.log(JSON.stringify(result,null,2));return;
    }
    for(const key of ['id','name','job','project','chat','question'])if(f[key]!==undefined)args[key]=f[key];if(f.confirm!==undefined){if(f.confirm!=='true')throw Error('--confirm 需要 true');args.confirm=true;}if(f.text!==undefined||f['text-file'])args.text=textArg(f,'text');
    args.action=action==='app'?words[1]:(action==='phone-ai'?'ai':action)+'.'+words[1];const result=await request(peer,'app',args);
    if(f.out){const file=path.resolve(f.out);fs.writeFileSync(file,JSON.stringify(result,null,2),{flag:'wx',mode:0o600});console.log(JSON.stringify({path:file}));}else console.log(JSON.stringify(result,null,2));return;
  }
  let method='execute',args;
  if(action==='control'){const op=words[1];if(!['begin','end'].includes(op))throw Error('control 必须是 begin 或 end');method='presence';args={actor:'ai',active:op==='begin',lease_seconds:numberArg(f,'lease',6,120,120)};}
  else if(action==='info'){method='info';args={};}
  else if(action==='disconnect'){method='session.close';args={};}
  else if(action==='terminal'){
    const operation=words[1];if(!['open','read','write','interrupt','close'].includes(operation))throw Error('未知终端操作');
    method='terminal.'+operation;args={};if(operation!=='open'){if(!f.session||!/^[a-f0-9-]{36}$/.test(f.session))throw Error('需要有效的 --session');args.session=f.session;}
    if(operation==='read')args.offset=numberArg(f,'offset',0,Number.MAX_SAFE_INTEGER,0);
    if(operation==='write')args.text=textArg(f,'text');
  }else{
    let tool,parameters={};
    if(action==='screenshot')tool='screen_capture';
    else if(action==='home')tool='screen_home';
    else if(action==='type'){tool='screen_type';parameters.text=textArg(f,'text');}
    else if(action==='tap'||action==='swipe'){
      tool='screen_'+action;for(const key of action==='tap'?['x','y']:['x','y','x2','y2'])parameters[key]=numberArg(f,key,0,1);
      if(action==='swipe')parameters.duration=numberArg(f,'duration',0.1,1.5,0.4);
    }else if(action==='shell'){tool='run_shell';parameters={command:textArg(f,'command'),timeout_seconds:numberArg(f,'timeout',1,120,30)};}
    else{
      tool=f.tool;if(!['read_file','write_file','list_directory'].includes(tool))throw Error('仅支持 read_file / write_file / list_directory');
      if(!f['args-file'])throw Error('需要 --args-file');parameters=JSON.parse(fs.readFileSync(f['args-file'],'utf8').replace(/^\uFEFF/,''));
      if(!parameters||typeof parameters!=='object'||Array.isArray(parameters))throw Error('工具参数必须是 JSON 对象');
    }
    args={tool,arguments:parameters,actor:tool.startsWith('screen_')?'ai':undefined};
  }
  const abort=new AbortController(),stop=()=>abort.abort();process.once('SIGINT',stop);process.once('SIGTERM',stop);
  try{
    const result=await request(peer,method,args,abort.signal);
    if(action==='screenshot'){
      if(typeof result.image_base64!=='string')throw Error('设备未返回截图');
      const bytes=Buffer.from(result.image_base64,'base64'),png=bytes.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10])),jpeg=bytes[0]===255&&bytes[1]===216;
      if(!png&&!jpeg)throw Error('设备返回的图片格式无效');
      const output=path.resolve(f.out||path.join('.agentgo','captures',Date.now()+'-'+crypto.randomUUID()+(png?'.png':'.jpg')));
      fs.mkdirSync(path.dirname(output),{recursive:true});fs.writeFileSync(output,bytes,{flag:'wx',mode:0o600});
      const {image_base64,...metadata}=result;console.log(JSON.stringify({device:peer.id,...metadata,path:output,bytes:bytes.length},null,2));
    }else{console.log(JSON.stringify({device:peer.id,result},null,2));if(action==='shell'&&Number(result.exit_code??result.exit??0)!==0)process.exitCode=1;}
  }finally{process.removeListener('SIGINT',stop);process.removeListener('SIGTERM',stop);}
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))main(process.argv.slice(2)).catch(error=>{console.error(JSON.stringify({error:error.message}));process.exitCode=1;});
