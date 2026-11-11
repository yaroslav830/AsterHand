// Interoperate with the shipping JS wire implementation, not a duplicate fixture.
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {seal,open,openFrame} from '../desktop/control-wire.mjs';
import {pairingSecret} from '../desktop/control-pairing.mjs';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const executable=path.resolve(root,process.argv[2]||'build/windows-native-test/AsterHand.Tests.exe');
const call=args=>{const r=spawnSync(executable,['--interop'],{input:JSON.stringify(args),encoding:'utf8',windowsHide:true,timeout:10000});assert.equal(r.status,0,r.stderr);return JSON.parse(r.stdout);};
const key=crypto.randomBytes(32).toString('hex'),pair=crypto.randomUUID(),payload={id:crypto.randomUUID(),ts:Date.now()/1000,text:'手机 ↔ Windows 原生 🔐'};
assert.equal(call({op:'open',packet:seal(pair,key,payload,'req'),key,direction:'req'}).text,payload.text);
assert.equal(open(call({op:'seal',pair,key,payload,direction:'res'}),key,'res').text,payload.text);
const ec=crypto.createECDH('prime256v1');ec.generateKeys();
const identity={private_key:ec.getPrivateKey().toString('base64'),public_key:ec.getPublicKey().toString('base64')};
const remoteIdentity=call({op:'identity'}),remote={...remoteIdentity,device_id:crypto.createHash('sha256').update(Buffer.from(remoteIdentity.public_key,'base64')).digest('hex')};
const local={...identity,device_id:crypto.createHash('sha256').update(ec.getPublicKey()).digest('hex')};
const expected=pairingSecret({identity},remote,pair);
assert.equal(call({op:'pair',identity:remoteIdentity,remote:local,id:pair}).key,expected);
const video=call({op:'frame',key,nonce:pair});
const frame=openFrame(key,pair,Buffer.from(video.data,'base64'));
assert.equal(frame.jpeg.toString(),'fixture-jpeg');assert.equal(frame.width,100);assert.equal(frame.height,200);
const report={passed:4,failed:0,checks:['JS request → native decrypt','native response → JS decrypt','P-256 pairing key matches existing JS protocol','native authenticated video → existing JS parser'],timeUtc:new Date().toISOString(),physicalPhoneTested:false};
const reportFile=path.join(path.dirname(executable),'native-interop-report.json');fs.writeFileSync(reportFile,JSON.stringify(report,null,2)+'\n');
console.log('Native / shipping JS interoperability: 4 passed; 0 failed.');
