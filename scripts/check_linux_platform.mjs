import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {attachLinuxPlatform, platformCapabilities} from '../desktop/linux/platform.mjs';

let passed = 0;
async function check(name, test) { await test(); passed++; console.log('PASS ' + name); }
function fixture(overrides = {}) {
  const calls = [];
  let screen = false, remote = false, captured = 0, clip = 'original clipboard';
  const hub = {state: {enabled: false, screenEnabled: false, peers: []}, work: '/default', available: () => true,
    async execute(method, args, owner) { calls.push({method, args, owner, work: this.work}); return {original: true, work: this.work}; },
    stream(id) { return {original: id}; }, receiveStream() { return 'original'; }};
  const options = {platform: 'linux', env: {DISPLAY: ':0', XDG_SESSION_TYPE: 'x11', PATH: '/bin'}, hasCommand: () => true,
    exec: async (command, args, opts) => { calls.push({command, args, opts}); return {stdout: command === 'xdotool' && args[0] === 'getdisplaygeometry' ? '1920 1080\n' : ''}; },
    getScreenEnabled: () => screen, getRemoteEnabled: () => remote,
    capture: async () => { captured++; return {jpeg: Buffer.from([255, 216, 255, 217]), width: 1280, height: 720, bounds: {x: -1280, y: 0, width: 1280, height: 720}}; },
    clipboard: {readText: () => clip, writeText: text => { clip = text; }}, ...overrides};
  const attached = attachLinuxPlatform(hub, options);
  return {hub, options, attached, calls, enableScreen() { screen = true; }, enableRemote() { remote = true; }, get captured() { return captured; }, get clip() { return clip; }, set clip(value) { clip = value; }};
}

await check('Wayland reports capture separately and refuses XWayland input', async () => {
  const caps = platformCapabilities({platform: 'linux', env: {WAYLAND_DISPLAY: 'wayland-0', DISPLAY: ':0'}, hasCommand: () => true, hasCapture: true});
  assert.equal(caps.session, 'wayland'); assert.equal(caps.screenCapture, true); assert.equal(caps.screenStream, false); assert.equal(caps.screenInput, false); assert.match(caps.inputReason, /portal/);
  const f = fixture({env: {WAYLAND_DISPLAY: 'wayland-0', DISPLAY: ':0'}}); f.enableScreen();
  await assert.rejects(f.hub.execute('execute', {tool: 'screen_tap', arguments: {x: 0.5, y: 0.5}}), /portal/); assert.equal(f.calls.length, 0);
  assert.throws(() => f.hub.stream('local', () => {}, () => {}), /persistent consented portal/); assert.equal(f.captured, 0); f.attached.close();
});
await check('Capture is blocked before user enables screen access', async () => {
  const f = fixture(); await assert.rejects(f.hub.execute('execute', {tool: 'screen_capture', arguments: {}}), /Enable screen access/); assert.equal(f.captured, 0);
  f.enableScreen(); const result = await f.hub.execute('execute', {tool: 'screen_capture', arguments: {}}); assert.equal(result.mime, 'image/jpeg'); assert.equal(result.width, 1280); assert.equal(f.captured, 1); f.attached.close();
});
await check('Remote requests are gated independently from local access', async () => {
  const f = fixture(); f.enableScreen(); await assert.rejects(f.hub.execute('execute', {tool: 'run_shell', arguments: {command: 'true'}}, 'remote-pair'), /Remote control is disabled/);
  await f.hub.execute('execute', {tool: 'screen_capture', arguments: {}}); assert.equal(f.captured, 1);
  f.enableRemote(); await f.hub.execute('execute', {tool: 'screen_capture', arguments: {}}, 'remote-pair'); assert.equal(f.captured, 2); f.attached.close();
});
await check('Normalized coordinates match selected monitor bounds including negative origin', async () => {
  const f = fixture(); f.enableScreen(); await f.hub.execute('execute', {tool: 'screen_capture', arguments: {}});
  await f.hub.execute('execute', {tool: 'screen_tap', arguments: {x: 1, y: 1}});
  assert.deepEqual(f.calls[0].args, ['mousemove', '--', '-1', '719', 'click', '1']);
  await assert.rejects(f.hub.execute('execute', {tool: 'screen_tap', arguments: {x: NaN, y: 0.1}}), /coordinates/);
  await assert.rejects(f.hub.execute('execute', {tool: 'screen_tap', arguments: {x: 1.1, y: 0.1}}), /coordinates/); f.attached.close();
});
await check('Repeated clicks at the same cursor position do not wait for movement', async () => {
  let cursor = null, completed = 0;
  const f = fixture({exec: async (command, args) => {
    if (args[0] === 'getdisplaygeometry') return {stdout: '1920 1080'};
    if (args[0] === 'mousemove') {
      const offset = args.indexOf('--') + 1, destination = args.slice(offset, offset + 2).join(',');
      // xdotool --sync waits for a movement event that never arrives at an unchanged destination.
      if (args.includes('--sync') && destination === cursor) return new Promise(() => {});
      cursor = destination; completed++;
    }
    return {stdout: ''};
  }});
  f.enableScreen();
  let timeout;
  try {
    await Promise.race([(async () => {
      for (let i = 0; i < 2; i++) await f.hub.execute('execute', {tool: 'screen_tap', arguments: {x: 0.5, y: 0.5}});
    })(), new Promise((_, reject) => { timeout = setTimeout(() => reject(Error('Repeated pointer action hung waiting for movement.')), 200); })]);
    assert.equal(completed, 2);
  } finally { clearTimeout(timeout); f.attached.close(); }
});
await check('Unicode paste preserves literal text and restores untouched clipboard', async () => {
  const f = fixture(); f.enableScreen(); const text = '中文 😀 $(touch nope) `uname`';
  await f.hub.execute('execute', {tool: 'screen_type', arguments: {text, replace: true}});
  assert.equal(f.clip, 'original clipboard'); assert.deepEqual(f.calls.map(c => c.args), [['key', '--clearmodifiers', 'ctrl+a'], ['key', '--clearmodifiers', 'ctrl+v']]);
  assert(!JSON.stringify(f.calls).includes(text)); f.attached.close();
});
await check('Concurrent clipboard changes are preserved', async () => {
  const f = fixture(); f.enableScreen(); f.options.exec = undefined;
  const promise = f.hub.execute('execute', {tool: 'screen_type', arguments: {text: 'paste me', replace: false}});
  await new Promise(resolve => setTimeout(resolve, 30)); f.clip = 'new user clipboard'; await promise;
  assert.equal(f.clip, 'new user clipboard'); f.attached.close();
});
await check('Async Electron clipboard finishes before paste and restores the original string', async () => {
  let clip='original async clipboard';
  const f=fixture({clipboard:{readText:async()=>clip,writeText:async text=>{await new Promise(resolve=>setTimeout(resolve,5));assert.equal(typeof text,'string');clip=text;}},exec:async(command,args)=>{if(args.includes('ctrl+v'))assert.equal(clip,'异步输入');return {stdout:'1920 1080'};}});
  f.enableScreen();
  try{await f.hub.execute('execute',{tool:'screen_type',arguments:{text:'异步输入'}});assert.equal(clip,'original async clipboard');}finally{f.attached.close();}
});
await check('Swipe releases mouse button even if interrupted', async () => {
  const abort = new AbortController();
  const f = fixture({exec: async (command, args) => { f.calls.push({command, args}); if (args.includes('mousedown')) abort.abort(); return {stdout: '1920 1080'}; }});
  f.enableScreen(); await assert.rejects(f.hub.execute('execute', {tool: 'screen_swipe', arguments: {x: 0, y: 0, x2: 1, y2: 1, duration: 0.2}}, 'local', abort.signal));
  assert(f.calls.some(c => c.args[0] === 'mouseup')); f.attached.close();
});
await check('Local project workspace is scoped without mutating hub or honoring remote override', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'asterhand-platform-'));
  const f = fixture(); try {
    const result = await f.hub.execute('execute', {tool: 'run_shell', arguments: {command: 'pwd'}, workspace: directory}); assert.equal(result.work, directory); assert.equal(f.hub.work, '/default');
    f.enableRemote(); const remote = await f.hub.execute('execute', {tool: 'run_shell', arguments: {command: 'pwd'}, workspace: directory}, 'remote-pair'); assert.equal(remote.work, '/default');
  } finally { f.attached.close(); fs.rmdirSync(directory); }
});
await check('Local stream returns actual frames and close stops further capture', async () => {
  const f = fixture(); f.enableScreen(); let frames = 0;
  const stop = f.hub.stream('local', frame => { assert.equal(frame[0], 255); frames++; }, error => { throw error; });
  await new Promise(resolve => setTimeout(resolve, 25)); assert.equal(frames, 1); stop();
  await new Promise(resolve => setTimeout(resolve, 200)); assert.equal(frames, 1); f.attached.close();
});
await check('Remote streams retain existing transport and unknown tools cannot bypass adapter', async () => {
  const f = fixture(); assert.deepEqual(f.hub.stream('remote', () => {}, () => {}), {original: 'remote'});
  await assert.rejects(f.hub.execute('execute', {tool: 'screen_unknown', arguments: {}}), /Unknown screen action/); f.attached.close();
});
console.log(JSON.stringify({suite: 'linux-platform', passed, failed: 0, realLinuxDesktop: false}));
