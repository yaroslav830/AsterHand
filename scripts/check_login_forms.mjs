import fs from 'node:fs';
import assert from 'node:assert/strict';
import {pathToFileURL} from 'node:url';
const playwright=await import(process.env.PLAYWRIGHT_MODULE_PATH?pathToFileURL(process.env.PLAYWRIGHT_MODULE_PATH).href:'playwright');
const browser=await playwright.chromium.launch({headless:true,...(process.env.BROWSER_EXECUTABLE?{executablePath:process.env.BROWSER_EXECUTABLE}:{})});
const source=fs.readFileSync(new URL('../Resources/chatgpt-login-forms.js',import.meta.url),'utf8');
try{
 for(const legacy of [false,true]){
  const page=await browser.newPage();
  await page.setContent('<form id="login"><input name="tag" value="one"><button name="intent" value="google">Google</button><input name="tag" value="two"><input name="disabled" disabled value="secret"><input type="file" name="attachment"></form><button form="login" name="intent" value="apple">Apple</button><form id="other"></form>');
  await page.evaluate(legacy=>{
   window.NativeFormData=FormData;window.activeButton=null;
   if(legacy){window.FormData=class extends NativeFormData{constructor(form){super(form,window.activeButton&&window.activeButton.form===form&&!window.activeButton.disabled?window.activeButton:undefined);}};}
   window.initialConstructor=FormData;
   window.routerSubmit=function(button){window.activeButton=button;try{
    let supportsSubmitter=false;try{new FormData(document.createElement('form'),0);}catch{supportsSubmitter=true;}
    const data=new FormData(button.form,button);if(!supportsSubmitter&&button.name)data.append(button.name,button.value);return [...data].map(([k,v])=>[k,typeof v==='string'?v:{name:v.name,size:v.size,type:v.type}]);
   }finally{window.activeButton=null;}};
  },legacy);
  const before=await page.evaluate(()=>routerSubmit(document.querySelector('button')));
  assert.equal(before.filter(([k])=>k==='intent').length,legacy?2:1,'Reproduce old WebKit duplicate intent before patch');
  await page.addScriptTag({content:source});
  const result=await page.evaluate(()=>{
   const first=document.querySelector('button'),external=document.querySelector('button[form]');
   const expected=button=>[...new NativeFormData(button.form,button)].map(([k,v])=>[k,typeof v==='string'?v:{name:v.name,size:v.size,type:v.type}]);
   const invalid=fn=>{try{fn();return null;}catch(e){return e.name;}};
   const saved=FormData;
   return {actual:routerSubmit(first),expected:expected(first),outside:routerSubmit(external),outsideExpected:expected(external),invalidType:invalid(()=>new FormData(first.form,0)),wrongOwner:invalid(()=>new FormData(document.querySelector('#other'),first)),enabled:!first.disabled,temporaryNodes:document.querySelectorAll('span,input[type=hidden]').length,constructorPreserved:FormData===initialConstructor};
  });
  assert.deepEqual(result.actual,result.expected);assert.deepEqual(result.outside,result.outsideExpected);
  assert.equal(result.invalidType,'TypeError');assert.equal(result.wrongOwner,'NotFoundError');assert.equal(result.enabled,true);assert.equal(result.temporaryNodes,0);assert.equal(result.constructorPreserved,!legacy);
  const installed=await page.evaluate(()=>{window.savedConstructor=FormData;return true;});
  await page.addScriptTag({content:source});assert.equal(await page.evaluate(()=>FormData===savedConstructor),true,'Repeated injection must preserve constructor');
  console.log(JSON.stringify({legacy_webkit_emulated:legacy,duplicate_intent_fixed:true,entry_order_and_repeated_fields_preserved:true,file_and_disabled_fields_preserved:true,external_submitter:true,native_errors_preserved:true,no_temporary_nodes:true,idempotent:installed}));
  await page.close();
 }
}finally{await browser.close();}

