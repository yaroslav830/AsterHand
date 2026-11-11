// Bounded protocol checks. Does not capture the screen or inspect user files.
import fs from 'node:fs';
import net from 'node:net';
import tls from 'node:tls';
import http from 'node:http';
import WebSocket from '../desktop/node_modules/ws/wrapper.mjs';
const config=JSON.parse(fs.readFileSync(new URL('../.private/remote/desktop.json',import.meta.url)));
if(process.argv[2])config.host=process.argv[2];
const version=Buffer.from('RFB 003.008\n');
const onlyVersion=data=>data.length===0 || data.equals(version);
const passive=await new Promise(resolve=>{
  const s=net.connect(config.port,config.host);let data=Buffer.alloc(0);
  s.on('data',chunk=>{data=Buffer.concat([data,chunk]);if(data.equals(version))s.write(version);});s.on('close',()=>resolve(onlyVersion(data)));s.on('error',e=>resolve(e.code==='ECONNRESET' && onlyVersion(data)));s.setTimeout(2500,()=>{s.destroy();resolve(false);});
});
const plainWS=await new Promise(resolve=>{
  const ws=new WebSocket(`ws://${config.host}:${config.port}/websockify`,['binary'],{origin:'http://127.0.0.1:18767'});let data=Buffer.alloc(0);
  const timer=setTimeout(()=>{ws.terminate();resolve(false);},3500);
  ws.on('message',chunk=>{data=Buffer.concat([data,chunk]);if(data.equals(version))ws.send(version);});ws.on('close',()=>{clearTimeout(timer);resolve(onlyVersion(data));});ws.on('error',e=>{clearTimeout(timer);resolve(e.code==='ECONNRESET' && onlyVersion(data));});
});
const invalidCert=await new Promise(resolve=>{
  const s=tls.connect({host:config.host,port:config.port,servername:'pocketcodex.local',rejectUnauthorized:true});
  s.on('secureConnect',()=>{s.destroy();resolve(false);});s.on('error',()=>resolve(true));s.setTimeout(3000,()=>{s.destroy();resolve(false);});
});
const session=JSON.parse(fs.readFileSync(new URL('../.private/remote/desktop-session.json',import.meta.url)));
const rejectedOrigin=(await fetch(session.url+'bootstrap',{headers:{Origin:'http://example.invalid'}})).status===403;
const rejectedHost=await new Promise(resolve=>{const req=http.get(session.url,{headers:{Host:'example.invalid'}},res=>{res.resume();resolve(res.statusCode===403);});req.on('error',()=>resolve(false));});
const results={plain_rfb_rejected:passive,plain_websocket_rejected:plainWS,untrusted_certificate_rejected:invalidCert,foreign_origin_rejected:rejectedOrigin,foreign_host_rejected:rejectedHost};
console.log(JSON.stringify(results,null,2));
if(Object.values(results).some(value=>!value))process.exitCode=1;
