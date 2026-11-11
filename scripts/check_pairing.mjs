import assert from 'node:assert/strict';import fs from 'node:fs';import os from 'node:os';import path from 'node:path';
import {ControlHub} from '../desktop/control-core.mjs';
const temp=fs.mkdtempSync(path.join(os.tmpdir(),'agentgo-pairing-'));
const a=new ControlHub(path.join(temp,'a'),{port:0,bind:'127.0.0.1',work:path.join(temp,'work-a')}),b=new ControlHub(path.join(temp,'b'),{port:0,bind:'0.0.0.0',work:path.join(temp,'work-b')});
await Promise.all([a,b].map(h=>new Promise(r=>h.server.listening?r():h.server.once('listening',r))));const results={};
try{
 const device={...b.pairing.info(),host:'127.0.0.1'};const id=device.device_id;b.state.name='Renamed';b.save();assert.equal(b.pairing.info().device_id,id);results.stable_identity_after_rename=true;
 b.state.pair_code_mode='fixed';b.state.pair_code_fixed='123456';assert.equal(b.pairing.info().pair_code,'123456');b.state.pair_code_expires=0;assert.equal(b.pairing.info().pair_code,'123456');results.fixed_code_survives_expiry=true;
 b.state.background=false;b.uiActive=false;assert.equal((await (await fetch(`http://127.0.0.1:${b.port}/info`)).json()).available,false);await assert.rejects(a.pairing.begin({...b.pairing.info(),host:'127.0.0.1'}));b.uiActive=true;b.uiUpdated=Date.now();assert.equal(b.available(),true);b.uiUpdated=Date.now()-6000;assert.equal(b.available(),false);b.state.background=true;results.background_switch_gates_requests=true;
 const first=await a.pairing.begin(device);assert.equal(first.status,'pending');assert.equal(a.state.peers.length,0);assert.equal(b.state.peers.length,0);results.default_pending_no_access=true;
 assert.equal(first.code,b.pairing.pending()[0].code);results.shared_verification_code=true;
 b.pairing.decide(first.id,'once');const granted=await a.pairing.poll(first.id);assert.equal(granted.mode,'once');assert.equal((await a.request(first.id,'info')).name,'Renamed');results.once_authenticated=true;
 await a.request(first.id,'session.close');await new Promise(r=>setTimeout(r,150));await assert.rejects(a.request(first.id,'info'));results.disconnect_revokes_once=true;
 const next=await a.pairing.begin(device);assert.equal(next.status,'pending');b.pairing.decide(next.id,'always');await a.pairing.poll(next.id);assert.equal(b.state.trust[a.pairing.info().device_id].mode,'always');results.always_stored_by_identity=true;
 const again=await a.pairing.begin({...device,host:'127.0.0.2'});assert.equal(again.status,'accepted');assert.equal((await a.request(again.id,'info')).name,'Renamed');results.changed_address_does_not_change_trust=true;
 b.pairing.setTrust(a.pairing.info().device_id,'deny');await assert.rejects(a.request(again.id,'info'));const denied=await a.pairing.begin(device);assert.equal(denied.status,'denied');results.deny_blocks_existing_and_future=true;
 b.pairing.setTrust(a.pairing.info().device_id,'ask');const ask=await a.pairing.begin(device);assert.equal(ask.status,'pending');b.pairing.decide(ask.id,'once');await a.pairing.poll(ask.id);b.state.peers.find(p=>p.id===ask.id).expires_at=Date.now()/1000-1;await assert.rejects(a.request(ask.id,'info'));results.once_expiry_enforced=true;
 await assert.rejects(a.pairing.begin({...device,device_id:'0'.repeat(64)}),/identity/);results.identity_substitution_denied=true;
}finally{await a.close();await b.close();const resolved=path.resolve(temp);if(!resolved.startsWith(path.resolve(os.tmpdir())+path.sep)||!path.basename(resolved).startsWith('agentgo-pairing-'))throw Error('Unexpected test directory');fs.rmSync(resolved,{recursive:true});}
console.log(JSON.stringify(results,null,2));
