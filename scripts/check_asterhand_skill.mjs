// Isolated client authentication and configuration tests; never uses real pairing keys.
import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {spawnSync,spawn} from 'node:child_process';
import {request,findConfig,recordStream,localControl} from '../skills/asterhand-skill/scripts/asterhand.mjs';
import {seal,open,sealFrame} from '../skills/asterhand-skill/scripts/control-wire.mjs';
const peer={id:crypto.randomUUID(),key:crypto.randomBytes(32).toString('hex'),host:'127.0.0.1',name:'Fixture'};
let mode='valid';
const server=http.createServer(async(req,res)=>{
  let body='';for await(const chunk of req)body+=chunk;
  const payload=open(JSON.parse(body),peer.key,'req');
  if(payload.method==='stream2'){res.writeHead(200,{'Content-Type':'application/octet-stream'});const frame=sealFrame(peer.key,payload.id,1,Buffer.from([255,216,255,217]),1,1),header=Buffer.alloc(4);header.writeUInt32BE(frame.length);res.end(Buffer.concat([header,frame]));return;}
  const value={id:mode==='nonce'?crypto.randomUUID():payload.id,ts:Date.now()/1000,result:mode==='denied'?{error:'fixture refusal'}:{ok:true}};
  const packet=seal(peer.id,peer.key,value,'res');if(mode==='tamper')packet.mac=Buffer.alloc(32).toString('base64');
  res.writeHead(200,{'Content-Type':'application/json'});res.end(JSON.stringify(packet));
});
await new Promise(r=>server.listen(0,'127.0.0.1',r));peer.port=server.address().port;
const temp=fs.mkdtempSync(path.join(os.tmpdir(),'agentgo-skill-test-')),results={};
try{
  assert.equal((await request(peer,'info')).ok,true);results.authenticated_reply=true;
  mode='nonce';await assert.rejects(request(peer,'info'),/身份不匹配/);results.wrong_response_identity_denied=true;
  mode='tamper';await assert.rejects(request(peer,'info'),/authentication failed/);results.tampered_reply_denied=true;
  mode='denied';await assert.rejects(request(peer,'info'),/fixture refusal/);results.remote_refusal_preserved=true;
  const directory=path.join(temp,'project','.private','control');fs.mkdirSync(directory,{recursive:true});
  const config=path.join(directory,'control.json');fs.writeFileSync(config,JSON.stringify({peers:[peer]}));
  const codex=path.join(temp,'codex');fs.mkdirSync(codex);fs.writeFileSync(path.join(codex,'agentgo.json'),JSON.stringify({project:path.join(temp,'project')}));
  assert.equal(findConfig(undefined,{CODEX_HOME:codex},codex),config);results.project_pointer=true;
  assert.equal(findConfig(undefined,{ASTERHAND_HOME:path.join(temp,'project')},temp),config);
  assert.equal(findConfig(undefined,{AGENTGO_HOME:path.join(temp,'project')},temp),config);results.new_and_legacy_environment=true;
  fs.writeFileSync(path.join(codex,'asterhand.json'),JSON.stringify({project:path.join(temp,'project')}));
  fs.writeFileSync(path.join(codex,'agentgo.json'),JSON.stringify({project:path.join(temp,'old-project')}));
  assert.equal(findConfig(undefined,{CODEX_HOME:codex},codex),config);results.new_pointer_preferred_legacy_preserved=true;
  const cli=path.resolve('skills/asterhand-skill/scripts/asterhand.mjs');
  const list=spawnSync(process.execPath,[cli,'--config',config,'list'],{encoding:'utf8',cwd:temp});
  assert.equal(list.status,0);assert.ok(!list.stdout.includes(peer.key));assert.equal(JSON.parse(list.stdout).devices[0].id,peer.id);results.list_never_prints_key=true;
  mode='valid';const run=args=>new Promise((resolve,reject)=>{const child=spawn(process.execPath,[cli,'--config',config,...args],{cwd:temp,windowsHide:true});let out='',err='';child.stdout.on('data',b=>out+=b);child.stderr.on('data',b=>err+=b);child.on('error',reject);child.on('exit',code=>resolve({code,out,err}));});
  const app=await run(['--device',peer.id,'app','capabilities']);assert.equal(app.code,0);assert.equal(JSON.parse(app.out).ok,true);assert.ok(!app.out.includes(peer.key));results.app_rpc_authenticated_no_key_output=true;
  mode='denied';const refused=await run(['--device',peer.id,'project','list']);assert.notEqual(refused.code,0);assert.match(refused.err,/fixture refusal/);results.app_refusal_preserved=true;
  mode='valid';const movie=path.join(temp,'fixture.mjpg');const video=await recordStream(peer,movie,2);assert.equal(video.frames,1);assert.deepEqual(fs.readFileSync(movie),Buffer.from([255,216,255,217]));results.encrypted_stream_decoded=true;
  await assert.rejects(recordStream(peer,movie,2),/EEXIST/);results.stream_refuses_overwrite=true;
  const sessionDir=path.join(temp,'project','.private','remote');fs.mkdirSync(sessionDir,{recursive:true});let writes=0;
  const prefix='/session/'+'a'.repeat(48)+'/',local=http.createServer(async(req,res)=>{let input='';for await(const b of req)input+=b;let result;
    if(req.url===prefix+'control/state'&&req.method==='GET')result={enabled:true};
    else if(req.url===prefix+'control/name'&&req.method==='POST'&&req.headers.origin==='http://127.0.0.1:'+local.address().port){writes++;result={name:JSON.parse(input).name};}
    else{res.writeHead(403);result={error:'unexpected request'};}res.end(JSON.stringify(result));});
  await new Promise(r=>local.listen(0,'127.0.0.1',r));fs.writeFileSync(path.join(sessionDir,'desktop-session.json'),JSON.stringify({url:'http://127.0.0.1:'+local.address().port+prefix}));
  try{assert.equal((await localControl(config,'state')).enabled,true);results.desktop_state_read=true;
    const rename=path.join(temp,'rename.json');fs.writeFileSync(rename,JSON.stringify({name:'Fixture PC'}));const renamed=await run(['desktop','name','--args-file',rename]);assert.equal(renamed.code,0);assert.equal(JSON.parse(renamed.out).name,'Fixture PC');assert.equal(writes,1);results.desktop_mutation_origin=true;
    const decision=await run(['desktop','decision','--args-file',rename]);assert.notEqual(decision.code,0);assert.match(decision.err,/confirm/);assert.equal(writes,1);results.desktop_grant_requires_confirmation=true;
    fs.writeFileSync(path.join(sessionDir,'desktop-session.json'),JSON.stringify({url:'https://example.invalid/'+prefix}));await assert.rejects(localControl(config,'state'),/无效/);results.desktop_rejects_non_loopback=true;
  }finally{await new Promise(r=>local.close(r));}
}finally{await new Promise(r=>server.close(r));fs.rmSync(temp,{recursive:true,force:true});}
console.log(JSON.stringify(results,null,2));
