// Legacy command path; the discoverable skill is asterhand-skill.
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {main} from '../../asterhand-skill/scripts/asterhand.mjs';
export * from '../../asterhand-skill/scripts/asterhand.mjs';
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))main(process.argv.slice(2)).catch(error=>{console.error(JSON.stringify({error:error.message}));process.exitCode=1;});
