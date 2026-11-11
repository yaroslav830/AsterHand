import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const source=fs.readFileSync(new URL('../Resources/chatgpt-login-compat.js',import.meta.url),'utf8');
function LegacyURL(input,base){return new URL(input,base);}
const sandbox={window:{URL:LegacyURL}};vm.runInNewContext(source,sandbox);
const fixtures=[['https://auth.openai.com/'],['/authorize','https://auth.openai.com'],['/relative'],['https://['],['http://127.0.0.1:43210/auth/callback'],['not a url'],['about:blank'],['', 'https://auth.openai.com'],[undefined]];
for(const input of fixtures){assert.equal(LegacyURL.canParse(...input),URL.canParse(...input));assert.equal(LegacyURL.parse(...input)?.href??null,URL.parse(...input)?.href??null);}
const canParse=LegacyURL.canParse;vm.runInNewContext(source,sandbox);assert.equal(LegacyURL.canParse,canParse);
const nativeParse=URL.canParse;vm.runInNewContext(source,{window:{URL}});assert.equal(URL.canParse,nativeParse);
console.log(JSON.stringify({url_cases:fixtures.length,repeat_injection_preserves_methods:true,native_methods_preserved:true}));
const listeners={};
const healthWindow={URL:LegacyURL,location:{href:'https://auth.openai.com/log-in'},addEventListener:(name,handler)=>listeners[name]=handler,fetch:async()=>({status:403,get body(){throw Error('Diagnostic must not inspect response body');}})};
vm.runInNewContext(source,{window:healthWindow});
await healthWindow.fetch('https://auth.openai.com/api/accounts/fixture',{method:'POST',body:'private-fixture'});
await healthWindow.fetch('https://unrelated.invalid/private',{method:'POST'});
listeners.unhandledrejection({reason:new TypeError('Promise.withResolvers is not a function; private-fixture')});
assert.deepEqual(Array.from(healthWindow.__asterHandLoginHealth),['fetch_post_403','web_type_error','js_stack_unmapped','missing_promise_resolvers']);
assert(!JSON.stringify(healthWindow.__asterHandLoginHealth).includes('private-fixture'));
const fetchWrapper=healthWindow.fetch;vm.runInNewContext(source,{window:healthWindow});assert.equal(healthWindow.fetch,fetchWrapper);
console.log(JSON.stringify({diagnostics_only_status_and_fixed_categories:true,unrelated_requests_not_recorded:true,fetch_not_wrapped_twice:true}));
const start=healthWindow.__asterHandLoginHealth.length;
listeners.error({error:{name:'TypeError',message:"undefined is not an object (evaluating 'p.duration')"},filename:'https://cdn.oaistatic.com/auth/assets/long-file-name-fixture123.js?private-fixture',lineno:20,colno:30});
assert.deepEqual(Array.from(healthWindow.__asterHandLoginHealth).slice(start),['web_type_error','js_expression_p_duration','js_asset_static_auth_s_assets_s_long-file-name-fixture123_d_js_line_20_column_30']);
assert(!JSON.stringify(healthWindow.__asterHandLoginHealth).includes('private-fixture'));
console.log(JSON.stringify({public_asset_location_without_query:true}));
const entries=[];
const legacyTiming={getEntriesByName:(name,type)=>entries.filter(e=>e.name===name&&e.entryType===type)};
for(const method of ['mark','measure']){
  legacyTiming[method]=function(name){assert.equal(this,legacyTiming);if(!arguments.length)throw new TypeError('Name required');if(name==='invalid')throw new SyntaxError('Missing start mark');entries.push({name,entryType:method,duration:method==='measure'?42:0});};
  legacyTiming[method==='mark'?'clearMarks':'clearMeasures']=name=>{for(let i=entries.length-1;i>=0;i--)if(entries[i].name===name&&entries[i].entryType===method)entries.splice(i,1);};
}
const timingWindow={URL:LegacyURL,performance:legacyTiming};vm.runInNewContext(source,{window:timingWindow});
assert.equal(entries.length,0,'Probes must not remain on timeline');
assert.equal(legacyTiming.mark('start').duration,0);assert.equal(legacyTiming.measure('elapsed').duration,42);
assert.throws(()=>legacyTiming.measure('invalid'),SyntaxError);assert.throws(()=>legacyTiming.measure(),TypeError);
const measureWrapper=legacyTiming.measure;vm.runInNewContext(source,{window:timingWindow});assert.equal(legacyTiming.measure,measureWrapper);
const nativeUserTiming={...legacyTiming,measure:()=>({duration:3})},nativeMeasure=nativeUserTiming.measure;
delete nativeUserTiming.mark;vm.runInNewContext(source,{window:{URL:LegacyURL,performance:nativeUserTiming}});assert.equal(nativeUserTiming.measure,nativeMeasure);
console.log(JSON.stringify({legacy_user_timing_returns_real_entry:true,errors_preserved:true,native_measure_untouched:true}));

const arrayContext=vm.createContext({});vm.runInContext('window=this; Array.prototype.at=undefined;',arrayContext);vm.runInContext(source,arrayContext);
for(const expression of ['[1,2,3].at(-1)===3','[1,2,3].at(0)===1','[1,2].at(2)===undefined','[1,2].at(Infinity)===undefined','[1,2].at(NaN)===1','[1,2].at(-1.8)===2',"Array.prototype.at.call({0:'x',length:1},-1)==='x'",'!Object.keys(Array.prototype).includes("at")'])assert(vm.runInContext(expression,arrayContext),expression);
vm.runInContext('savedAt=Array.prototype.at',arrayContext);vm.runInContext(source,arrayContext);assert(vm.runInContext('savedAt===Array.prototype.at',arrayContext));
assert.throws(()=>vm.runInContext('Array.prototype.at.call(null,0)',arrayContext));assert.throws(()=>vm.runInContext('[1].at(Symbol())',arrayContext));
console.log(JSON.stringify({array_at_negative_and_generic_cases:true,array_native_method_preserved:true}));

const formListeners={},form={},button={tagName:'BUTTON',type:'submit',name:'intent',value:'google',form,disabled:false};
const doc={addEventListener:(n,h)=>formListeners[n]=h};function OldArray(){}
const formWindow={URL:LegacyURL,Array:OldArray,document:doc};vm.runInNewContext(source,{window:formWindow});
function submit(trusted,nativeButton){const e={isTrusted:trusted,target:form};if(nativeButton)e.submitter=nativeButton;formListeners.click({isTrusted:trusted,target:button});formListeners.submit(e);return e;}
assert.equal(submit(true).submitter,button);assert.equal(submit(false).submitter,undefined);
const nativeButton={};assert.equal(submit(true,nativeButton).submitter,nativeButton);
const empty={isTrusted:true,target:form};formListeners.submit(empty);assert.equal(empty.submitter,undefined);
const other={isTrusted:true,target:{}};formListeners.click({isTrusted:true,target:button});formListeners.submit(other);assert.equal(other.submitter,undefined);
console.log(JSON.stringify({legacy_submitter_preserves_actual_clicked_button:true,native_submitter_and_untrusted_events_untouched:true}));
