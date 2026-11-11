import fs from 'node:fs';
import net from 'node:net';
import path from 'node:path';

const limit=16*1024*1024;
export function frame(value){const body=Buffer.from(JSON.stringify(value));if(!body.length||body.length>limit)throw Error('Local MCP message too large');const header=Buffer.alloc(4);header.writeUInt32BE(body.length);return Buffer.concat([header,body]);}
export function receiveFrame(socket){return new Promise((resolve,reject)=>{let size=0,expected=0,chunks=[];function clean(){socket.off('data',data);socket.off('error',failure);socket.off('close',closed);}function failure(e){clean();reject(e);}function closed(){failure(Error('Local AsterHand bridge closed'));}function data(chunk){size+=chunk.length;chunks.push(chunk);if(size>limit+4)return failure(Error('Local MCP message too large'));if(!expected&&size>=4){const prefix=Buffer.concat(chunks);expected=prefix.readUInt32BE();if(expected<1||expected>limit)return failure(Error('Invalid local MCP message length'));}if(expected&&size>=expected+4){if(size!==expected+4)return failure(Error('Unexpected trailing MCP data'));try{const value=JSON.parse(Buffer.concat(chunks).subarray(4));clean();resolve(value);}catch(e){failure(e);}}}socket.on('data',data);socket.once('error',failure);socket.once('close',closed);});}

export function bridgeDescriptor(config){
 if(path.basename(config)!=='mcp-bridge.json')return null;
 const stat=fs.lstatSync(config);if(!stat.isFile()||stat.size>4096||process.platform!=='win32'&&(stat.uid!==process.getuid()||(stat.mode&0o077)!==0))throw Error('AsterHand MCP endpoint is not private to this user');
 const value=JSON.parse(fs.readFileSync(config,'utf8').replace(/^\uFEFF/,''));
 if(value.version!==1||value.platform!==process.platform||typeof value.address!=='string')throw Error('Unsupported local AsterHand MCP endpoint');
 if(process.platform==='win32'){if(!/^\\\\\.\\pipe\\AsterHand\.MCP\.[a-f0-9]{32}$/.test(value.address))throw Error('Invalid AsterHand named pipe');}
 else{if(!path.isAbsolute(value.address)||path.basename(value.address)!=='mcp.sock')throw Error('Invalid AsterHand socket');const folder=fs.lstatSync(path.dirname(value.address)),socket=fs.lstatSync(value.address);if(!folder.isDirectory()||folder.uid!==process.getuid()||(folder.mode&0o077)!==0||!socket.isSocket()||socket.uid!==process.getuid())throw Error('AsterHand socket is not private to this user');}
 return value;
}
export async function bridgeCall(config,route,body,signal){
 const endpoint=bridgeDescriptor(config);if(!endpoint)throw Error('No native MCP endpoint');signal?.throwIfAborted();
 const socket=net.createConnection(endpoint.address),abort=()=>socket.destroy(Error('Local MCP call cancelled'));socket.on('error',()=>{});socket.setTimeout(135000,()=>socket.destroy(Error('Local MCP call timed out')));signal?.addEventListener('abort',abort,{once:true});
 try{const result=receiveFrame(socket);socket.write(frame({route,body}));const reply=await result;if(reply.error)throw Error(reply.error);return reply.result;}finally{signal?.removeEventListener('abort',abort);socket.destroy();}
}
