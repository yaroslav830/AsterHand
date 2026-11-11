// Real MCP SDK client -> stdio process -> encrypted loopback receiver. No real devices or accounts.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import http from 'node:http';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
import {Client} from '@modelcontextprotocol/sdk/client/index.js';
import {StdioClientTransport} from '@modelcontextprotocol/sdk/client/stdio.js';
import {seal,open} from '../skills/asterhand-skill/scripts/control-wire.mjs';

const temp=fs.mkdtempSync(path.join(os.tmpdir(),'asterhand-mcp-')),key=crypto.randomBytes(32).toString('hex');
const peer={id:crypto.randomUUID(),key,host:'127.0.0.1',port:0,name:'Fixture'},calls=[],checks={};let cancelled=false;
const receiver=http.createServer(async(req,res)=>{let raw='';for await(const b of req)raw+=b;const payload=open(JSON.parse(raw),key,'req');calls.push(payload);let result={ok:true,key};
  if(payload.method==='info')result={platform:'fixture',key};
  if(payload.method==='execute'){
    if(payload.args.tool==='screen_capture')result={image_base64:'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jbxkAAAAASUVORK5CYII=',width:1,height:1};
    if(payload.args.tool==='run_shell'){
      if(payload.args.arguments.command==='fail')result={exit_code:7,output:'fixture failure'};
      if(payload.args.arguments.command==='echo-secret')result={error:'remote error '+key};
      if(payload.args.arguments.command==='wait'){req.socket.once('close',()=>{cancelled=true;});return;}
    }
  }
  if(payload.method==='app'&&payload.args.action==='attachment.chunk'){const p=payload.args;assert.equal(p.offset,0);assert.equal(Buffer.from(p.data,'base64').toString(),'fixture attachment');result={complete:true,attachment:{name:p.name,bytes:p.total}};}
  if(payload.method==='app'&&payload.args.action==='settings.api-key')result={saved:true,echo:payload.args.key};
  res.end(JSON.stringify(seal(peer.id,key,{id:payload.id,ts:Date.now()/1000,result},'res')));
});
await new Promise(r=>receiver.listen(0,'127.0.0.1',r));peer.port=receiver.address().port;
const config=path.join(temp,'control.json');fs.writeFileSync(config,JSON.stringify({peers:[peer]}));
const transport=new StdioClientTransport({command:process.execPath,args:[fileURLToPath(new URL('./server.mjs',import.meta.url))],env:{...process.env,ASTERHAND_CONFIG:config},stderr:'pipe'});
const client=new Client({name:'asterhand-test',version:'1.0.0'});let stderr='';transport.stderr?.on('data',b=>stderr+=b);
const call=(name,args={})=>client.callTool({name,arguments:args});const obj=result=>result.structuredContent??JSON.parse(result.content.find(x=>x.type==='text').text);
try{
  await client.connect(transport);checks.stdio_initialize=true;
  const list=await client.listTools();assert.ok(list.tools.length>=20);assert.ok(list.tools.find(t=>t.name==='screenshot').annotations.readOnlyHint);checks.tools_and_annotations=true;
  const devices=await call('devices_list');assert.equal(obj(devices).devices[0].id,peer.id);assert.ok(!JSON.stringify(devices).includes(key));checks.no_pairing_keys=true;
  assert.equal(obj(await call('device_info',{device:peer.id})).platform,'fixture');checks.encrypted_device_info=true;
  const image=await call('screenshot',{device:peer.id});assert.equal(image.content[0].type,'image');assert.equal(image.content[0].mimeType,'image/png');checks.native_image_content=true;
  const before=calls.length;const bad=await call('screen',{device:peer.id,action:'tap',x:1.2,y:.5});assert.equal(bad.isError,true);assert.equal(calls.length,before);checks.invalid_coordinates_no_dispatch=true;
  const refused=await call('projects',{device:peer.id,action:'delete',parameters:{id:crypto.randomUUID()}});assert.equal(refused.isError,true);assert.equal(calls.length,before);checks.delete_requires_explicit_confirmation=true;
  const stale=await call('phone_ai',{device:peer.id,action:'answer',parameters:{text:'test'}});assert.equal(stale.isError,true);assert.equal(calls.length,before);checks.answer_requires_job_question_chat=true;
  const forwarded=await call('application',{device:peer.id,action:'device.app',parameters:{id:crypto.randomUUID(),arguments:{action:'device.decide',id:crypto.randomUUID(),mode:'always'}}});assert.equal(forwarded.isError,true);assert.equal(calls.length,before);checks.forwarding_cannot_skip_confirm=true;
  await call('projects',{device:peer.id,action:'list',parameters:{action:'services.stop'}});assert.equal(calls.at(-1).args.action,'project.list');checks.operation_cannot_be_overridden=true;
  const fail=await call('shell',{device:peer.id,command:'fail'});assert.equal(fail.isError,true);assert.equal(obj(fail).exit_code,7);checks.nonzero_shell_is_error=true;
  const error=await call('shell',{device:peer.id,command:'echo-secret'});assert.equal(error.isError,true);assert.ok(!JSON.stringify(error).includes(key));checks.secret_errors_redacted=true;
  const privateKey=path.join(temp,'fixture-key.txt');fs.writeFileSync(privateKey,'fixture-api-key-not-a-real-credential');const saved=await call('settings',{device:peer.id,action:'api-key',parameters:{key_file:privateKey}});assert.equal(obj(saved).saved,true);assert.ok(!JSON.stringify(saved).includes('fixture-api-key-not-a-real-credential'));assert.equal(calls.at(-1).args.key,'fixture-api-key-not-a-real-credential');checks.private_key_file_no_readback=true;
  const file=path.join(temp,'fixture.txt');fs.writeFileSync(file,'fixture attachment');const uploaded=await call('attachments',{device:peer.id,action:'upload',parameters:{path:file,project:crypto.randomUUID(),chat:crypto.randomUUID()}});assert.equal(obj(uploaded).complete,true);checks.encrypted_attachment_upload=true;
  const abort=new AbortController();const pending=client.callTool({name:'shell',arguments:{device:peer.id,command:'wait'}},undefined,{signal:abort.signal});await new Promise(r=>setTimeout(r,100));abort.abort();await assert.rejects(pending);for(let n=0;n<20&&!cancelled;n++)await new Promise(r=>setTimeout(r,50));assert.ok(cancelled);checks.cancellation_closes_remote_socket=true;
  fs.writeFileSync(config,JSON.stringify({peers:[]}));assert.equal((await call('device_info',{device:peer.id})).isError,true);checks.revocation_reloaded_per_call=true;
  fs.writeFileSync(config,'{"key":"DO_NOT_ECHO_THIS_SECRET",BROKEN');const malformed=await call('devices_list');assert.equal(malformed.isError,true);assert.ok(!JSON.stringify(malformed).includes('DO_NOT_ECHO_THIS_SECRET'));checks.malformed_config_not_echoed=true;
  assert.equal(stderr,'');checks.no_stdout_or_stderr_debug_leaks=true;
}finally{await client.close();await new Promise(r=>receiver.close(r));assert.ok(path.resolve(temp).startsWith(path.join(path.resolve(os.tmpdir()),'asterhand-mcp-')));fs.rmSync(temp,{recursive:true,force:true});}
console.log(JSON.stringify({checks,passed:Object.keys(checks).length},null,2));
