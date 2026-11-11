import fs from 'node:fs';import assert from 'node:assert/strict';import {pathToFileURL} from 'node:url';
const {chromium}=await import(process.env.PLAYWRIGHT_MODULE_PATH?pathToFileURL(process.env.PLAYWRIGHT_MODULE_PATH).href:'playwright');
const browser=await chromium.launch({headless:true,...(process.env.BROWSER_EXECUTABLE?{executablePath:process.env.BROWSER_EXECUTABLE}:{})});
const source=fs.readFileSync(new URL('../Resources/chatgpt-login-compat.js',import.meta.url),'utf8');
try{for(const legacy of [false,true]){
 const page=await browser.newPage();await page.addInitScript({content:`window.__asterHandLegacyCSP=${legacy};\n`+source});
 await page.route('https://auth.openai.com/log-in',route=>route.fulfill({headers:{'content-type':'text/html','content-security-policy':"default-src 'none'; script-src 'nonce-private-fixture-nonce'"},body:`<script nonce="private-fixture-nonce">window.allowedLoads=0;setTimeout(function(){for(var address of ['https://sentinel.openai.com/backend-api/sentinel/sdk.js','https://chatgpt.com/sentinel/20260810913b/sdk.js','https://unrelated.invalid/sdk.js','https://sentinel.openai.com/backend-api/sentinel/sdk.js?untrusted=1']){var s=document.createElement('script');s.src=address;document.head.appendChild(s);}},10);</script>`}));
 await page.route(/^https:\/\/(sentinel.openai.com|chatgpt.com)\//,route=>route.fulfill({contentType:'text/javascript',body:'window.allowedLoads++;'}));
 await page.goto('https://auth.openai.com/log-in');await page.waitForTimeout(200);
 const result=await page.evaluate(()=>({loaded:allowedLoads,nonces:[...document.scripts].slice(1).map(s=>!!s.nonce),health:__asterHandLoginHealth,wrapper:Node.prototype.appendChild.__asterHandNonce===true}));
 assert.equal(result.loaded,legacy?2:0);assert.deepEqual(result.nonces,legacy?[true,true,false,false]:[false,false,false,false]);assert.equal(result.wrapper,legacy);assert(!JSON.stringify(result.health).includes('private-fixture-nonce'));assert(!JSON.stringify(result.health).includes('untrusted'));
 if(legacy){assert(result.health.includes('legacy_script_nonce'));assert(result.health.includes('csp_script_blocked_other'));}
 console.log(JSON.stringify({legacy_csp:legacy,official_scripts_only:true,unknown_hosts_and_queries_blocked:true,no_nonce_in_diagnostics:true,website_policy_retained:true}));await page.close();
}}finally{await browser.close();}
