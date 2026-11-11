// Measures actual received frame rate without saving screen contents.
import fs from 'node:fs';
import path from 'node:path';
import {ControlHub} from '../desktop/control-core.mjs';
const root=path.resolve(import.meta.dirname,'..');const client=Object.create(ControlHub.prototype);
client.state=JSON.parse(fs.readFileSync(path.join(root,'.private/control/control.json')));
const target=process.argv[2]==='local'?'local':client.state.peers.find(p=>p.host===(process.argv[2]||'192.168.1.34'))?.id;
if(!target)throw Error('Paired target missing');
const abort=new AbortController();let frames=0,first=0,last=0,bytes=0;
await new Promise((resolve,reject)=>{const timeout=setTimeout(()=>{abort.abort();reject(Error('Stream timeout'));},20000);client.stream(target,frame=>{const now=performance.now();if(!first)first=now;last=now;bytes+=frame.length;if(++frames>=180){clearTimeout(timeout);abort.abort();resolve();}},error=>{clearTimeout(timeout);abort.abort();reject(error);},abort.signal);});
const result={target:process.argv[2]||'192.168.1.34',frames,seconds:(last-first)/1000,received_fps:(frames-1)*1000/(last-first),megabytes:bytes/1048576};
console.log(JSON.stringify(result,null,2));fs.writeFileSync(path.join(root,'diagnostics',target==='local'?'control-windows-stream.json':'control-phone-stream.json'),JSON.stringify(result,null,2));
