// Read-only command/session tests on the explicitly paired iPhone.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {ControlHub} from '../desktop/control-core.mjs';
const client=Object.create(ControlHub.prototype);client.state=JSON.parse(fs.readFileSync(new URL('../.private/control/control.json',import.meta.url)));
const peer=client.state.peers.find(p=>p.host===(process.argv[2]||'192.168.1.34'));if(!peer)throw Error('Paired phone missing');
const call=(method,args,signal)=>client.request(peer.id,method,args,signal);
const results={};const shell=await call('execute',{tool:'run_shell',arguments:{command:'printf AGENTGO_CONTROL_OK',timeout_seconds:5}});assert.equal(shell.output,'AGENTGO_CONTROL_OK');results.phone_shell=true;
const s=await call('terminal.open',{});let offset=0,text='';
async function readUntil(expression){for(let n=0;n<40;n++){await new Promise(r=>setTimeout(r,100));const r=await call('terminal.read',{session:s.session,offset});if(r.error)throw Error(r.error);offset=r.next_offset;text+=r.output;if(expression.test(text))return;}throw Error('Terminal output missing: '+JSON.stringify(text));}
try{
 assert.equal(s.mode,'persistent-command-shell');
 await call('terminal.write',{session:s.session,text:"agentgoTest=AGENTGO_IOS_TERMINAL_OK\nprintf '\\n%s\\n' \"$agentgoTest\"\n"});
 await readUntil(/(?:^|\r?\n)AGENTGO_IOS_TERMINAL_OK\r?\n/);results.terminal_state_persists=true;results.terminal_uid=s.uid;
 await call('terminal.write',{session:s.session,text:'sleep 30\n'});await new Promise(r=>setTimeout(r,250));const stopped=await call('terminal.interrupt',{session:s.session});assert.equal(stopped.ended,true);results.terminal_interrupt=true;
}finally{await call('terminal.close',{session:s.session});}
const next=await call('terminal.open',{});const closed=await call('terminal.close',{session:next.session});assert.equal(closed.closed,true);results.terminal_reopen_and_close=true;
const abort=new AbortController();const work=call('execute',{tool:'run_shell',arguments:{command:'sleep 10',timeout_seconds:12}},abort.signal);setTimeout(()=>abort.abort(),250);await assert.rejects(work);await new Promise(r=>setTimeout(r,300));const started=performance.now();const after=await call('execute',{tool:'run_shell',arguments:{command:'printf AGENTGO_CANCEL_OK',timeout_seconds:5}});assert.equal(after.output,'AGENTGO_CANCEL_OK');assert.ok(performance.now()-started<2500);results.remote_shell_cancel=true;
console.log(JSON.stringify(results,null,2));fs.writeFileSync(new URL('../diagnostics/control-phone-terminal.json',import.meta.url),JSON.stringify(results,null,2));
