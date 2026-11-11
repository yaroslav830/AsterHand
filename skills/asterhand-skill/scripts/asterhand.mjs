// Compatibility launcher only: MCP is the primary interface.
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {cli} from './project-runtime.mjs';
export const {main,findConfig,loadPeers,resolvePeer,request,recordStream,localControl,uploadAttachment}=cli;
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))main(process.argv.slice(2)).catch(error=>{console.error(JSON.stringify({error:error.message}));process.exitCode=1;});
