// Shared implementation identity and upload failure semantics; no device credentials.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import * as shared from '../shared/asterhand-client.mjs';
import * as wire from '../shared/control-wire.mjs';
import * as cli from '../cli/asterhand.mjs';
import * as skill from '../skills/asterhand-skill/scripts/asterhand.mjs';
import * as legacy from '../skills/asterhand-control/scripts/asterhand.mjs';
import * as desktopWire from '../desktop/control-wire.mjs';
import * as skillWire from '../skills/asterhand-skill/scripts/control-wire.mjs';

const root=path.resolve(import.meta.dirname,'..'),release=JSON.parse(fs.readFileSync(path.join(root,'version.json'),'utf8')),checks={};
for(const name of ['request','findConfig','loadPeers','resolvePeer','localControl','recordStream','uploadAttachment'])for(const adapter of [cli,skill,legacy])assert.equal(adapter[name],shared[name]);checks.adapters_share_same_functions=true;
for(const name of Object.keys(wire))for(const adapter of [desktopWire,skillWire])assert.equal(adapter[name],wire[name]);checks.desktop_mcp_cli_share_crypto=true;
for(const entry of ['cli/asterhand.mjs','skills/asterhand-skill/scripts/asterhand.mjs','skills/asterhand-control/scripts/asterhand.mjs','skills/agentgo-control/scripts/agentgo.mjs']){const result=spawnSync(process.execPath,[path.join(root,entry),'--version'],{encoding:'utf8',cwd:os.tmpdir(),windowsHide:true});assert.equal(result.status,0,result.stderr);assert.equal(result.stdout.trim(),`AsterHand ${release.version} (build ${release.build})`);}checks.legacy_entrypoints_work_outside_workspace=true;

const temp=fs.mkdtempSync(path.join(os.tmpdir(),'asterhand-shared-')),file=path.join(temp,'fixture.txt'),project=crypto.randomUUID(),chat=crypto.randomUUID(),calls=[];
try{
  const bytes=Buffer.alloc(192*1024+13,97);fs.writeFileSync(file,bytes);
  const complete=await shared.uploadAttachment({file,project,chat,call:async(action,p)=>{calls.push({action,...p});const offset=p.offset+Buffer.from(p.data,'base64').length;return offset===bytes.length?{complete:true,attachment:{bytes:offset}}:{offset};}});
  assert.equal(complete.attachment.bytes,bytes.length);assert.equal(calls.length,2);assert.equal(calls[0].id,calls[1].id);assert.equal(calls[1].offset,192*1024);assert.deepEqual(Buffer.concat(calls.map(p=>Buffer.from(p.data,'base64'))),bytes);checks.multipart_upload_round_trip=true;
  calls.length=0;await assert.rejects(shared.uploadAttachment({file,project,chat,call:async(action,p)=>{calls.push(action);return action==='attachment.chunk'?{offset:7}:{ok:true};}}),/确认/);assert.deepEqual(calls,['attachment.chunk','attachment.cancel']);checks.bad_ack_not_retried_cleanup_once=true;
  calls.length=0;await assert.rejects(shared.uploadAttachment({file,project,chat,call:async(action,p)=>{calls.push(action);return action==='attachment.chunk'?{complete:true}:{ok:true};}}),/提前完成/);assert.deepEqual(calls,['attachment.chunk','attachment.cancel']);checks.early_completion_rejected=true;
  calls.length=0;await assert.rejects(shared.uploadAttachment({file,project,chat,call:async(action,p)=>{calls.push(action);if(action==='attachment.cancel')return {};if(p.offset)throw Error('fixture transport failure');return {offset:192*1024};}}),/fixture transport failure/);assert.deepEqual(calls,['attachment.chunk','attachment.chunk','attachment.cancel']);checks.transport_failure_preserved_no_replay=true;
  const abort=new AbortController();abort.abort();let sent=0;await assert.rejects(shared.uploadAttachment({file,project,chat,signal:abort.signal,call:async()=>{sent++;return {};}}),/取消/);assert.equal(sent,0);checks.pre_cancel_no_remote_changes=true;
  const midway=new AbortController();sent=0;await assert.rejects(shared.uploadAttachment({file,project,chat,signal:midway.signal,call:async()=>{sent++;midway.abort();return {offset:192*1024};}}),/取消/);assert.equal(sent,1);checks.cancel_does_not_send_more_chunks=true;
  fs.writeFileSync(file,'');await assert.rejects(shared.uploadAttachment({file,project,chat,call:async()=>{throw Error('must not send');}}),/MiB/);checks.empty_upload_refused=true;
  fs.writeFileSync(file,Buffer.alloc(8*1024*1024+1));await assert.rejects(shared.uploadAttachment({file,project,chat,call:async()=>{throw Error('must not send');}}),/MiB/);checks.oversize_upload_refused_before_send=true;
  const config=path.join(temp,'control.json'),id=crypto.randomUUID(),device_id=crypto.randomBytes(32).toString('hex');fs.writeFileSync(config,JSON.stringify({peers:[{id,device_id,host:'127.0.0.1',incoming:false}]}));assert.equal(shared.resolvePeer(config,device_id).id,id);fs.writeFileSync(config,JSON.stringify({peers:[]}));assert.throws(()=>shared.resolvePeer(config,id),/唯一/);checks.exact_identity_and_revocation=true;
}finally{assert.ok(path.resolve(temp).startsWith(path.join(path.resolve(os.tmpdir()),'asterhand-shared-')));fs.rmSync(temp,{recursive:true,force:true});}
console.log(JSON.stringify({checks,passed:Object.keys(checks).length},null,2));
