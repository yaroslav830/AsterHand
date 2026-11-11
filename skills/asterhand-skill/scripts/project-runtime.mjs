// Bootstrap only. Control code lives in the AsterHand project, never in copied skill folders.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
function valid(root){return fs.existsSync(path.join(root,'shared/asterhand-client.mjs'))&&fs.existsSync(path.join(root,'cli/asterhand.mjs'));}
function project(){
  const source=fileURLToPath(new URL('../../../',import.meta.url));if(valid(source))return source;
  const codex=process.env.CODEX_HOME||path.join(os.homedir(),'.codex');
  for(const name of ['asterhand.json','agentgo.json'])try{const pointer=JSON.parse(fs.readFileSync(path.join(codex,name),'utf8').replace(/^\uFEFF/,''));if(typeof pointer.project==='string'&&path.isAbsolute(pointer.project)&&valid(pointer.project))return pointer.project;}catch{}
  for(const root of [process.env.ASTERHAND_HOME,process.env.AGENTGO_HOME])if(root&&valid(path.resolve(root)))return path.resolve(root);
  throw Error('AsterHand 共用客户端未找到。请运行项目中的 install_asterhand_skill.ps1 更新本机项目指针；不要复制配对密钥。');
}
export const projectRoot=project();
export const cli=await import(pathToFileURL(path.join(projectRoot,'cli/asterhand.mjs')));
export const wire=await import(pathToFileURL(path.join(projectRoot,'shared/control-wire.mjs')));
