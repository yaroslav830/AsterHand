import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import http from 'node:http';
import assert from 'node:assert/strict';
import {fileURLToPath,pathToFileURL} from 'node:url';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const assets=path.join(root,'android/app/src/main/assets/ui');
const output=path.join(root,'.private/user-guide-tests');fs.mkdirSync(output,{recursive:true});
const catalog=JSON.parse(fs.readFileSync(path.join(root,'Resources/localizations.json'),'utf8'));
const guide=JSON.parse(fs.readFileSync(path.join(root,'Resources/user-guide.json'),'utf8'));
const allowed=['index.html','app.js','i18n.js','user-guide.js','style.css','mark.png','guide/android-home.jpg','guide/android-settings.jpg','guide/android-permission.jpg'];
const moduleName=process.env.PLAYWRIGHT_MODULE_PATH||path.join(os.homedir(),'.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright/index.mjs');
const {chromium}=await import(pathToFileURL(moduleName).href);
const chrome=['C:/Program Files/Google/Chrome/Application/chrome.exe','C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'].find(p=>fs.existsSync(p));
const browser=await chromium.launch({headless:true,...(chrome?{executablePath:chrome}:{})});
const server=http.createServer((req,res)=>{
 const name=new URL(req.url,'http://fixture.local').pathname.slice(1)||'index.html';
 if(!allowed.includes(name)){res.writeHead(404);res.end();return;}
 const mime=name.endsWith('.js')?'application/javascript':name.endsWith('.css')?'text/css':name.endsWith('.jpg')?'image/jpeg':name.endsWith('.png')?'image/png':'text/html';
 res.writeHead(200,{'content-type':mime,'content-security-policy':"default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'none'; frame-src 'none'; base-uri 'none'; form-action 'none'"});
 res.end(fs.readFileSync(path.join(assets,name)));
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const origin=`http://127.0.0.1:${server.address().port}`;
let passed=0;const failures=[];
function translated(locale,key){return locale==='zh-CN'?key:catalog.messages[key]?.[locale]||key;}
async function mock(page,initial){
 await page.addInitScript(initial=>{
  const s={guideCompleted:false,guideAutoEligible:true,systemLanguages:['en'],dark:false,provider:0,providers:['OpenAI API','DeepSeek','Claude API','ChatGPT'],mode:'NORMAL',settings:{uiLanguage:'en',appearance:'light'},projects:[{id:'demo',name:'Demo project',chats:[{id:'chat',title:'Demo chat'}]}],currentProject:'demo',currentChat:'chat',messages:[],task:{},voice:{},remote:{pending:[]},...initial};
  if(sessionStorage.getItem('guideDone')==='yes')s.guideCompleted=true;
  window.__state=s;window.__calls=[];
  window.__poll=patch=>{Object.assign(s,patch);window.asterState(JSON.parse(JSON.stringify(s)));};
  window.AsterNative={invoke:(op,raw)=>{window.__calls.push({op,args:JSON.parse(raw||'{}')});return '{}';},dispatch:(op,raw,id)=>{
   window.__calls.push({op,args:JSON.parse(raw||'{}')});
   setTimeout(()=>{
    let result={};
    if(op==='state')result=JSON.parse(JSON.stringify(s));
    else if(op==='guideComplete'){
     if(window.__failSave)result={error:'无法保存引导进度，请重试。'};
     else{s.guideCompleted=true;sessionStorage.setItem('guideDone','yes');window.__poll({});}
    }else result={error:'Unexpected native operation: '+op};
    window.asterResult(id,result);
   },0);
  }};
 },initial);
}
async function layout(page,label){
 const sizes=await page.evaluate(()=>({viewport:innerWidth,width:document.documentElement.scrollWidth,main:[main.clientWidth,main.scrollWidth]}));
 assert(sizes.width<=sizes.viewport+2,label+': document overflow');
 assert(sizes.main[1]<=sizes.main[0]+2,label+': content overflow');
 const missing=await page.locator('.guide-figure img').evaluateAll(async images=>{
  await Promise.all(images.map(image=>image.decode().catch(()=>{})));
  return images.filter(image=>!image.naturalWidth).map(image=>image.src);
 });
 assert.deepEqual(missing,[],label+': missing screenshot');
 for(const button of await page.locator('.guide-controls button').all()){
  const box=await button.boundingBox(),viewport=page.viewportSize();
  assert(box&&box.y>=0&&box.y+box.height<=viewport.height+1,label+': navigation must stay visible');
 }
}
async function test(name,viewport,dark,locale,initial,work){
 const context=await browser.newContext({viewport,colorScheme:dark?'dark':'light'});
 const page=await context.newPage(),errors=[],network=[];
 page.on('pageerror',e=>errors.push(e.message));
 await context.route('**/*',route=>{if(route.request().url().startsWith(origin+'/'))return route.continue();network.push(route.request().url());return route.abort();});
 const t=key=>translated(locale,key);
 try{
  await mock(page,{dark,settings:{uiLanguage:locale},...initial});await page.goto(origin+'/index.html');
  await page.locator('#header .brand').waitFor();
  await work(page,t);
  assert.deepEqual(errors,[]);assert.deepEqual(network,[]);
  assert.deepEqual(await page.evaluate(()=>__calls.filter(c=>!['state','haptic','guideComplete'].includes(c.op))),[],'Guide must never request permissions, tools, microphone or sign-in');
  passed++;
 }catch(e){failures.push({name,viewport,dark,locale,error:e.message});await page.screenshot({path:path.join(output,`${name}-${locale}-${viewport.width}-${dark}-failure.png`)}).catch(()=>{});}
 finally{await context.close();}
}
try{
 for(const viewport of [{width:320,height:568},{width:412,height:870},{width:870,height:412}])for(const dark of [false,true])for(const locale of catalog.languages){
  await test('first-launch',viewport,dark,locale,{},async(page,t)=>{
   assert.equal(await page.locator('html').getAttribute('lang'),locale);
   assert.equal(await page.getByRole('heading',{level:1}).textContent(),t(guide.steps[0].title));
   for(let step=0;step<5;step++){
    assert.equal(await page.getByRole('progressbar').getAttribute('aria-valuenow'),String(step+1));
    await layout(page,'step '+step);
    if(step===1){
     const image=page.locator('.guide-figure img'),before=(await image.boundingBox()).height;
     await page.getByRole('button',{name:t('查看大图'),exact:true}).click();
     assert((await image.boundingBox()).height>before*1.5,'Enlarging the onboarding screenshot must increase its visible height');
     await page.getByRole('button',{name:t('收起图片'),exact:true}).click();
     await page.evaluate(()=>document.getElementById('main').scrollTop=0);
    }
    await page.evaluate(()=>__poll({}));
    assert.equal(await page.getByRole('progressbar').getAttribute('aria-valuenow'),String(step+1),'Polling must preserve the page');
    if(step===2){await page.getByRole('button',{name:t('上一步'),exact:true}).click();assert.equal(await page.getByRole('progressbar').getAttribute('aria-valuenow'),'2');await page.getByRole('button',{name:t('下一步'),exact:true}).click();}
    if(viewport.width===412&&locale==='zh-CN')await page.screenshot({path:path.join(output,`onboarding-${step+1}-${dark?'dark':'light'}.png`)});
    if(step<4)await page.getByRole('button',{name:t('下一步'),exact:true}).click();
   }
   assert.equal(await page.evaluate(()=>__calls.filter(c=>c.op==='guideComplete').length),0);
   await page.getByRole('button',{name:t('开始使用'),exact:true}).click();
   await page.getByRole('button',{name:t('设置'),exact:true}).waitFor();
   assert.equal(await page.evaluate(()=>__state.guideCompleted),true);
   await page.reload();await page.getByRole('button',{name:t('设置'),exact:true}).waitFor();
   assert.equal(await page.getByRole('progressbar').count(),0,'Completed guide must not repeat after relaunch');
   await page.getByRole('button',{name:t('设置'),exact:true}).click();
   await page.getByRole('button',{name:new RegExp('^'+t('使用指南'))}).click();
   for(const topic of guide.topics){
    await page.getByRole('button',{name:t(topic.title),exact:true}).click();await layout(page,topic.id);
    if(topic.androidImage){const image=page.locator('.guide-figure img');assert((await image.getAttribute('src')).startsWith('guide/android-'));await page.getByRole('button',{name:t('查看大图'),exact:true}).click();assert(await page.locator('.guide-figure.expanded').count());await layout(page,'expanded '+topic.id);}
    await page.getByRole('button',{name:t('返回'),exact:true}).click();
   }
   await page.getByRole('button',{name:t('重新查看入门引导'),exact:true}).click();
   await page.getByRole('button',{name:t('暂时跳过'),exact:true}).click();
   await page.getByRole('heading',{name:t('了解功能，从这里开始'),exact:true}).waitFor();
  });
 }
 const viewport={width:375,height:812};
 await test('skip-and-relaunch',viewport,false,'en',{},async(page,t)=>{await page.getByRole('button',{name:t('暂时跳过'),exact:true}).click();await page.getByRole('button',{name:'Settings',exact:true}).waitFor();await page.reload();await page.getByRole('button',{name:'Settings',exact:true}).waitFor();assert.equal(await page.getByRole('progressbar').count(),0);});
 await test('finish-to-connection',viewport,false,'en',{},async(page,t)=>{for(let i=0;i<4;i++)await page.getByRole('button',{name:'Next',exact:true}).click();await page.getByRole('button',{name:t('去连接 AI'),exact:true}).click();await page.getByRole('heading',{name:t('选择服务商'),exact:true}).waitFor();assert.equal(await page.evaluate(()=>__state.guideCompleted),true);});
 await test('failed-save-and-back',viewport,false,'en',{},async(page)=>{await page.evaluate(()=>{__failSave=true;asterBack();});await page.locator('#toast.show').waitFor();assert.equal(await page.evaluate(()=>__state.guideCompleted),false);assert.equal(await page.getByRole('progressbar').count(),1);await page.evaluate(()=>{__failSave=false;asterBack();});await page.getByRole('button',{name:'Settings',exact:true}).waitFor();});
 for(const [name,initial] of [['active-task',{task:{running:true}}],['voice-shortcut',{guideAutoEligible:false}],['active-voice',{voice:{active:true}}],['pending-pairing',{remote:{pending:[{id:'test',name:'Example request',code:'123456'}]}}],['login-callback',{settings:{uiLanguage:'en',signingIn:true}}]]){
  await test(name,viewport,false,'en',initial,async(page)=>{await page.getByRole('button',{name:'Settings',exact:true}).waitFor();assert.equal(await page.getByRole('progressbar').count(),0);assert.equal(await page.evaluate(()=>__state.guideCompleted),false);});
 }
}finally{await browser.close();await new Promise(resolve=>server.close(resolve));}
fs.writeFileSync(path.join(output,'report.json'),JSON.stringify({fixture_only:true,passed,failures},null,2));
console.log(JSON.stringify({fixture_only:true,passed,failures,output}));
if(failures.length)process.exitCode=1;
