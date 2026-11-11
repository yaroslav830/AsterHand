import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {spawn} from 'node:child_process';
import readline from 'node:readline';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {seal,open,sealFrame,openFrame,LIMIT} from '../desktop/control-wire.mjs';
import {pairingSecret,identity} from '../desktop/control-pairing.mjs';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const classpath=[path.join(root,'.private/android-ai-tests'),path.join(root,'.build-deps/android-ai-tests/json-20240303.jar')].join(path.delimiter);
const java=spawn(process.env.JAVA||'java',['-Dfile.encoding=UTF-8','-cp',classpath,'com.pocketagent.RemoteControlWireTest'],{cwd:root,stdio:['pipe','pipe','pipe'],windowsHide:true});
const lines=readline.createInterface({input:java.stdout});const pending=[];let error='';java.stderr.on('data',c=>error+=c);lines.on('line',line=>{const p=pending.shift();if(p){try{p.resolve(JSON.parse(line));}catch(e){p.reject(e);}}});java.on('error',e=>{for(const p of pending.splice(0))p.reject(e);});java.on('exit',code=>{for(const p of pending.splice(0))p.reject(Error('Java fixture stopped '+code+': '+error));});
const call=arg=>new Promise((resolve,reject)=>{pending.push({resolve,reject});java.stdin.write(JSON.stringify(arg)+'\n');});
let checks=0;const check=(value,label)=>{assert(value,label);checks++;};
try{
 const j=(await call({op:'identity'})).result;assert(j);const local={};identity(local);const id=crypto.randomUUID(),remote={public_key:j.public_key,device_id:crypto.createHash('sha256').update(Buffer.from(j.public_key,'base64')).digest('hex')};
 const key=pairingSecret(local,remote,id);const fromJava=await call({op:'secret',identity:j,remote:identity(local),id});check(fromJava.result===key,'JCA and Node P256 ECDH derive same pairing secret');
 const payload={id:crypto.randomUUID(),ts:Date.now()/1000,method:'execute',args:{tool:'read_file',arguments:{path:'你好.txt'}}};
 for(const direction of ['req','res']){
  const jpacket=(await call({op:'seal',id,key,payload,direction})).result;assert.deepEqual(open(jpacket,key,direction),payload);checks++;
  const answer=await call({op:'open',packet:seal(id,key,payload,direction),key,direction});assert.deepEqual(answer.result,payload);checks++;
 }
 const packet=seal(id,key,payload,'req');check(!!(await call({op:'open',packet,key,direction:'res'})).error,'Direction substitution rejected');
 const tampered={...packet,mac:Buffer.alloc(32).toString('base64')};check(!!(await call({op:'open',packet:tampered,key,direction:'req'})).error,'Tampered MAC rejected');
 check(!!(await call({op:'open',packet:seal(id,key,{...payload,ts:Date.now()/1000-100},'req'),key,direction:'req'})).error,'Expired request rejected');
 check(!!(await call({op:'open',packet:seal(id,key,{...payload,ts:String(Date.now()/1000)},'req'),key,direction:'req'})).error,'Timestamp type enforced');
 check(!!(await call({op:'open',packet:{...packet,data:'A'.repeat(LIMIT+1)},key,direction:'req'})).error,'Ciphertext size bounded');
 const frame=(await call({op:'frame',key,nonce:payload.id})).result;const opened=openFrame(key,payload.id,Buffer.from(frame,'base64'));check(opened.sequence===3&&opened.width===393&&opened.height===852&&opened.source===7,'Java frame header matches Node');check(opened.jpeg.equals(Buffer.from([255,216,255,217])),'Java frame image preserved');
 const nframe=sealFrame(key,payload.id,9,Buffer.from([255,216,255,217]),12,34,88);const jframe=await call({op:'openFrame',key,nonce:payload.id,packet:nframe.toString('base64')});const plain=Buffer.from(jframe.result,'base64');check(plain.readUInt32BE(0)===9&&plain.readUInt32BE(12)===88,'Node frame header matches Java');check(plain.subarray(16).equals(Buffer.from([255,216,255,217])),'Node frame image preserved');
 check(!!(await call({op:'openFrame',key,nonce:crypto.randomUUID(),packet:nframe.toString('base64')})).error,'Frame is connection-bound');
 for(const size of [0,1,2,3,17,257]){const value=crypto.randomBytes(size).toString('base64');check((await call({op:'base64',value})).result===value,'Base64 boundary '+size);}
 console.log(JSON.stringify({checks,java_node_p256_pairing:true,bidirectional_packets:true,encrypted_frames:true,tamper_expiry_direction_size_checks:true,real_device:false}));
}finally{java.stdin.end();lines.close();java.kill();}

