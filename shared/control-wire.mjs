// AsterHand control v1: encrypt-then-MAC; independent directional keys.
import crypto from 'node:crypto';
export const LIMIT = 2 * 1024 * 1024;
function key(secret, purpose) {
  if (!/^[a-f0-9]{64}$/.test(secret)) throw Error('Invalid pairing key');
  return crypto.createHmac('sha256', Buffer.from(secret,'hex')).update('AgentGo/v1/'+purpose).digest();
}
export function seal(pair, secret, payload, direction) {
  const iv=crypto.randomBytes(16), cipher=crypto.createCipheriv('aes-256-cbc',key(secret,'encryption/'+direction),iv);
  const data=Buffer.concat([cipher.update(JSON.stringify(payload)),cipher.final()]).toString('base64');
  const packet={v:1,pair,iv:iv.toString('base64'),data};
  packet.mac=crypto.createHmac('sha256',key(secret,'authentication/'+direction)).update(`v1\n${direction}\n${pair}\n${packet.iv}\n${data}`).digest('base64');
  return packet;
}
export function open(packet, secret, direction) {
  if (packet?.v!==1 || !/^[a-f0-9-]{36}$/.test(packet.pair) || typeof packet.data!=='string' || packet.data.length>LIMIT) throw Error('Invalid encrypted packet');
  const iv=Buffer.from(packet.iv||'','base64'), mac=Buffer.from(packet.mac||'','base64');
  const expected=crypto.createHmac('sha256',key(secret,'authentication/'+direction)).update(`v1\n${direction}\n${packet.pair}\n${packet.iv}\n${packet.data}`).digest();
  if (iv.length!==16 || mac.length!==32 || !crypto.timingSafeEqual(mac,expected)) throw Error('Pairing authentication failed');
  const decipher=crypto.createDecipheriv('aes-256-cbc',key(secret,'encryption/'+direction),iv);
  const result=JSON.parse(Buffer.concat([decipher.update(Buffer.from(packet.data,'base64')),decipher.final()]).toString('utf8'));
  if (typeof result.id!=='string' || result.id.length>80 || !Number.isFinite(result.ts) || Math.abs(Date.now()/1000-result.ts)>90) throw Error('Expired packet');
  return result;
}
export function invitation(peer, host, port, name) {
  return 'agentgo://pair/'+Buffer.from(JSON.stringify({v:1,pair:peer.id,key:peer.key,host,port,name})).toString('base64url');
}
export function parseInvitation(value) {
  if (typeof value!=='string' || value.length>4096 || !value.startsWith('agentgo://pair/')) throw Error('Invalid invitation');
  const p=JSON.parse(Buffer.from(value.slice(15),'base64url').toString());
  if(p.v!==1 || !/^[a-f0-9-]{36}$/.test(p.pair) || !/^[a-f0-9]{64}$/.test(p.key) || !/^[a-zA-Z0-9.:-]{1,253}$/.test(p.host) || !Number.isInteger(p.port) || p.port<1 || p.port>65535)throw Error('Invalid invitation');
  return p;
}
export function sealFrame(secret,nonce,sequence,jpeg,width=0,height=0,source=sequence){
  const direction='stream/'+nonce,header=Buffer.alloc(16);header.writeUInt32BE(sequence,0);header.writeUInt32BE(width,4);header.writeUInt32BE(height,8);header.writeUInt32BE(source,12);
  const iv=crypto.randomBytes(16),cipher=crypto.createCipheriv('aes-256-cbc',key(secret,'encryption/'+direction),iv);const body=Buffer.concat([iv,cipher.update(Buffer.concat([header,jpeg])),cipher.final()]);
  return Buffer.concat([body,crypto.createHmac('sha256',key(secret,'authentication/'+direction)).update(body).digest()]);
}
export function openFrame(secret,nonce,packet){
  if(packet.length<80||packet.length>LIMIT)throw Error('Invalid video frame');const direction='stream/'+nonce,body=packet.subarray(0,-32),mac=packet.subarray(-32);const expected=crypto.createHmac('sha256',key(secret,'authentication/'+direction)).update(body).digest();if(!crypto.timingSafeEqual(mac,expected))throw Error('Video authentication failed');
  const decipher=crypto.createDecipheriv('aes-256-cbc',key(secret,'encryption/'+direction),body.subarray(0,16));const plain=Buffer.concat([decipher.update(body.subarray(16)),decipher.final()]);if(plain.length<18)throw Error('Invalid video body');return {sequence:plain.readUInt32BE(),width:plain.readUInt32BE(4),height:plain.readUInt32BE(8),source:plain.readUInt32BE(12),jpeg:plain.subarray(16)};
}
