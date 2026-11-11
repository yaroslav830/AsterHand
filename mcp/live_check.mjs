// Read-only smoke check against one explicitly selected real paired device.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {Client} from '@modelcontextprotocol/sdk/client/index.js';
import {StdioClientTransport} from '@modelcontextprotocol/sdk/client/stdio.js';
const device=process.argv[2];if(!device)throw Error('Pass one exact pairing UUID or stable device_id.');
const client=new Client({name:'asterhand-live-check',version:'1.0.0'});
const transport=new StdioClientTransport({command:process.execPath,args:[fileURLToPath(new URL('./server.mjs',import.meta.url))],env:{...process.env,ASTERHAND_HOME:fileURLToPath(new URL('..',import.meta.url))},stderr:'pipe'});
const report={device},call=async(name,args={})=>{const result=await client.callTool({name,arguments:args},undefined,{timeout:150000});if(result.isError)throw Error(result.content.find(x=>x.type==='text')?.text||name+' failed');return result;};
try{
  await client.connect(transport);const catalog=await client.listTools();report.tools=catalog.tools.length;
  const list=(await call('devices_list')).structuredContent;report.paired_devices=list.devices.length;
  const selected=list.devices.filter(p=>p.id===device||p.device_id===device);if(selected.length!==1)throw Error('Selected device not uniquely paired');
  const info=(await call('device_info',{device})).structuredContent;report.platform=info.platform;report.authenticated=true;
  const status=(await call('phone_ai',{device,action:'status'})).structuredContent;report.ai_status_read=true;report.ai_running=!!status.running;
  const image=(await call('screenshot',{device})).content.find(x=>x.type==='image');if(!image)throw Error('No native MCP image returned');
  const directory=fileURLToPath(new URL('../.private/mcp/',import.meta.url));fs.mkdirSync(directory,{recursive:true});const output=path.join(directory,'capture-'+crypto.randomUUID()+(image.mimeType==='image/png'?'.png':'.jpg'));fs.writeFileSync(output,Buffer.from(image.data,'base64'),{flag:'wx',mode:0o600});report.native_image=true;report.image=output;
}finally{await client.close();console.log(JSON.stringify(report));}
