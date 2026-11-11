// Shared AsterHand client: MCP, CLI and compatibility launchers use this implementation.
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import http from 'node:http';
import crypto from 'node:crypto';
import {seal,open,openFrame,LIMIT} from './control-wire.mjs';
import {bridgeCall} from './mcp-bridge.mjs';

export async function localControl(config,route,body,signal){
  if(isNativeConfig(config))return bridgeCall(config,route,body,signal);
  const session=JSON.parse(fs.readFileSync(path.resolve(path.dirname(config),'../..','.private/remote/desktop-session.json'),'utf8')),base=new URL(session.url);
  if(base.protocol!=='http:'||base.hostname!=='127.0.0.1'||!/^\/session\/[a-f0-9]{48}\/$/.test(base.pathname))throw Error('无效的本机控制中心地址');
  const response=await fetch(new URL('control/'+route,base),{method:body?'POST':'GET',headers:body?{'Content-Type':'application/json',Origin:base.origin}:{},body:body?JSON.stringify(body):undefined,signal:AbortSignal.timeout(45000),redirect:'error'});const result=await response.json();if(!response.ok||result.error)throw Error(result.error||'控制中心拒绝请求');return result;
}
export function recordStream(peer,output,seconds=10,signal){
  const nonce=crypto.randomUUID(),packet=seal(peer.id,peer.key,{id:nonce,ts:Date.now()/1000,method:'stream2',args:{fps:30}},'req'),body=JSON.stringify(packet);let frames=0,sequence=0,buffer=Buffer.alloc(0),fd;
  return new Promise((resolve,reject)=>{const started=Date.now();let finished=false;const req=http.request({hostname:peer.host,port:peer.port,path:'/rpc',method:'POST',signal,headers:{'Content-Type':'application/json','Content-Length':Buffer.byteLength(body)}},res=>{
    if(res.statusCode!==200){req.destroy(Error('设备未允许串流'));return;}
    try{fs.mkdirSync(path.dirname(output),{recursive:true});fd=fs.openSync(output,'wx',0o600);}catch(e){req.destroy(e);return;}
    res.on('data',chunk=>{try{buffer=Buffer.concat([buffer,chunk]);if(buffer.length>4*1024*1024)throw Error('串流缓存超过上限');while(buffer.length>=4){const size=buffer.readUInt32BE();if(size<80||size>LIMIT)throw Error('串流帧大小无效');if(buffer.length<size+4)break;const frame=openFrame(peer.key,nonce,buffer.subarray(4,size+4));buffer=buffer.subarray(size+4);if(frame.sequence<=sequence)throw Error('串流帧重复');sequence=frame.sequence;if(frame.jpeg[0]!==255||frame.jpeg[1]!==216)throw Error('串流不是 JPEG');fs.writeSync(fd,frame.jpeg);frames++;if(frames>=1800){finish();return;}}}catch(e){finish(e);}});res.on('end',()=>finish(frames?null:Error('串流无画面')));res.on('error',finish);
  });
  const timer=setTimeout(()=>finish(frames?null:Error('串流超时或无画面')),seconds*1000);const finish=error=>{if(finished)return;finished=true;clearTimeout(timer);req.destroy();if(fd!==undefined)fs.closeSync(fd);error?reject(error):resolve({path:output,frames,seconds:(Date.now()-started)/1000});};req.on('error',finish);req.end(body);
  });
}

export function findConfig(explicit,env=process.env,cwd=process.cwd()){
  if(explicit)return path.resolve(explicit);
  if(env.ASTERHAND_DATA_DIR||env.ASTERHAND_HOME||env.AGENTGO_HOME){const home=env.ASTERHAND_DATA_DIR||env.ASTERHAND_HOME||env.AGENTGO_HOME,native=path.resolve(home,'mcp-bridge.json');return fs.existsSync(native)?native:path.resolve(home,'.private/control/control.json');}
  const native=process.platform==='linux'?path.join(env.XDG_DATA_HOME||path.join(os.homedir(),'.local','share'),'asterhand','mcp-bridge.json'):process.platform==='win32'?path.join(env.APPDATA||path.join(os.homedir(),'AppData','Roaming'),'AsterHand','Windows','mcp-bridge.json'):null;
  if(native&&fs.existsSync(native))return native;
  if(process.platform==='darwin'){const installed=path.join(os.homedir(),'Library','Application Support','AsterHand','.private','control','control.json');if(fs.existsSync(installed))return installed;}
  for(let dir=path.resolve(cwd);;dir=path.dirname(dir)){
    const candidate=path.join(dir,'.private/control/control.json');if(fs.existsSync(candidate))return candidate;
    if(path.dirname(dir)===dir)break;
  }
  const codex=env.CODEX_HOME||path.join(os.homedir(),'.codex');
  for(const name of ['asterhand.json','agentgo.json']){const pointer=path.join(codex,name);if(fs.existsSync(pointer)){
    const p=JSON.parse(fs.readFileSync(pointer,'utf8').replace(/^\uFEFF/,''));
    if(typeof p.project==='string')return path.resolve(p.project,'.private/control/control.json');
  }}
  throw Error('未找到 AsterHand 配对配置；请运行控制中心的 Codex 接入安装命令，或设置 ASTERHAND_HOME。');
}
export const isNativeConfig=config=>path.basename(config)==='mcp-bridge.json';
export async function listPeers(config,signal){if(!isNativeConfig(config))return loadPeers(config);const state=await localControl(config,'state',undefined,signal);return (state.peers||[]).filter(p=>p.host&&p.incoming!==true);}
export async function recordCaptures(call,output,seconds,signal){
 const started=Date.now(),end=started+seconds*1000;let count=0,fd;
 try{do{signal?.throwIfAborted();const response=await call(),jpeg=Buffer.from(response.image_base64||'','base64');if(jpeg.length<4||jpeg[0]!==255||jpeg[1]!==216||jpeg[jpeg.length-2]!==255||jpeg[jpeg.length-1]!==217)throw Error('Receiver did not return a complete JPEG frame');if(fd===undefined){fs.mkdirSync(path.dirname(output),{recursive:true});fd=fs.openSync(output,'wx',0o600);}fs.writeSync(fd,jpeg);count++;if(Date.now()<end)await new Promise(resolve=>setTimeout(resolve,220));}while(Date.now()<end&&count<1800);return {path:output,frames:count,seconds:(Date.now()-started)/1000,mode:'authenticated-snapshot-sequence'};}finally{if(fd!==undefined)fs.closeSync(fd);}
}
export function loadPeers(config){
  let state;try{state=JSON.parse(fs.readFileSync(config,'utf8').replace(/^\uFEFF/,''));}catch{throw Error('AsterHand 配对配置无法读取；原文件未修改。');}
  if(!Array.isArray(state.peers))throw Error('无效的 AsterHand 配对配置');
  return state.peers.filter(p=>p.host&&p.incoming!==true);
}
export function resolvePeer(config,device){
  const matches=loadPeers(config).filter(p=>p.id===device||p.device_id===device);
  if(matches.length!==1)throw Error('未找到唯一已配对设备，请先列出设备并使用精确标识。');
  return matches[0];
}
export async function uploadAttachment({file,project,chat,call,signal}){
  if(typeof file!=='string'||!file||typeof project!=='string'||!project||typeof chat!=='string'||!chat||typeof call!=='function')throw Error('上传需要 file、project、chat 和传输接口');
  const stat=fs.statSync(file);if(!stat.isFile()||stat.size<1||stat.size>8*1024*1024)throw Error('附件必须在 1 字节到 8 MiB 之间');
  if(signal?.aborted)throw Error('上传已取消，请先检查目标附件');
  const bytes=fs.readFileSync(file);if(bytes.length!==stat.size)throw Error('读取期间附件已变化');
  const id=crypto.randomUUID();let complete=false;
  try{
    for(let offset=0;offset<bytes.length;offset+=192*1024){
      if(signal?.aborted)throw Error('上传取消；请检查目标附件');
      const expected=Math.min(offset+192*1024,bytes.length);
      const result=await call('attachment.chunk',{id,name:path.basename(file),project,chat,total:bytes.length,offset,data:bytes.subarray(offset,expected).toString('base64')});
      if(result.complete){if(expected!==bytes.length)throw Error('附件提前完成，结果需要核对');complete=true;return result;}
      if(result.offset!==expected)throw Error('附件分块确认不匹配');
    }
    throw Error('附件未完成');
  }finally{if(!complete&&!signal?.aborted)try{await call('attachment.cancel',{id});}catch{}}
}
export function request(peer,method,args={},signal){
  if(!/^[a-f0-9-]{36}$/.test(peer.id)||!/^[a-f0-9]{64}$/.test(peer.key)||typeof peer.host!=='string'||!/^[a-zA-Z0-9.:-]{1,253}$/.test(peer.host)||!Number.isInteger(peer.port)||peer.port<1||peer.port>65535)throw Error('无效的配对设备');
  const id=crypto.randomUUID(),packet=seal(peer.id,peer.key,{id,ts:Date.now()/1000,method,args},'req'),body=JSON.stringify(packet);
  if(Buffer.byteLength(body)>LIMIT)throw Error('请求超过大小限制');
  return new Promise((resolve,reject)=>{
    const req=http.request({hostname:peer.host,port:peer.port,path:'/rpc',method:'POST',signal,headers:{'Content-Type':'application/json','Content-Length':Buffer.byteLength(body)}},res=>{
      let size=0;const chunks=[];
      res.on('data',chunk=>{size+=chunk.length;if(size>LIMIT){req.destroy(Error('响应超过大小限制'));return;}chunks.push(chunk);});
      res.on('error',reject);
      res.on('end',()=>{try{
        if(res.statusCode!==200)throw Error('设备拒绝请求；请检查被控开关、配对和网络');
        const envelope=JSON.parse(Buffer.concat(chunks).toString('utf8')),result=open(envelope,peer.key,'res');
        if(envelope.pair!==peer.id||result.id!==id)throw Error('响应身份不匹配');
        if(!result.result||typeof result.result!=='object'||Array.isArray(result.result))throw Error('无效的控制响应');
        if(result.result.error)throw Error(String(result.result.error));resolve(result.result);
      }catch(error){reject(error);}});
    });
    const deadline=setTimeout(()=>req.destroy(Error('远端请求超时')),130000);deadline.unref();
    req.on('close',()=>clearTimeout(deadline));req.on('error',reject);req.end(body);
  });
}
