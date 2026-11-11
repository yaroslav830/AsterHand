import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const source=fs.readFileSync(new URL('../Resources/chatgpt-login-streams.js',import.meta.url),'utf8');
const descriptors={pipeTo:Object.getOwnPropertyDescriptor(ReadableStream.prototype,'pipeTo'),pipeThrough:Object.getOwnPropertyDescriptor(ReadableStream.prototype,'pipeThrough')};
const env={ReadableStream,TextEncoder,TextDecoder,WeakMap,AbortController,Promise,Uint8Array,ArrayBuffer,Symbol};env.window=env;env.self=env;
async function all(readable){const reader=readable.getReader(),chunks=[];try{while(true){const r=await reader.read();if(r.done)return chunks;chunks.push(r.value);}}finally{reader.releaseLock();}}
try{
  vm.runInNewContext(source,env);
  assert.equal(env.ReadableStream,ReadableStream,'Preserve native readable streams');
  assert.equal(typeof env.TransformStream,'function');assert.equal(typeof env.WritableStream,'function');
  const encoder=new env.TextEncoderStream(),encoded=all(encoder.readable),writer=encoder.writable.getWriter();
  const chunks=['A','\uD83D','','\uDE00','中','\uD800'];for(const s of chunks)await writer.write(s);await writer.close();
  const expected=new TextEncoder().encode(chunks.join(''));assert.deepEqual(Buffer.concat((await encoded).map(x=>Buffer.from(x))),Buffer.from(expected));
  assert.equal(encoder.encoding,'utf-8');assert.throws(()=>env.TextEncoderStream(),/requires new/);
  const decoder=new env.TextDecoderStream(),decoded=all(decoder.readable),sink=decoder.writable.getWriter();
  for(const byte of expected)await sink.write(new Uint8Array([byte]));await sink.close();assert.equal((await decoded).join(''),new TextDecoder().decode(expected));
  const nativeFetchBody=new Response('native 中文 😀').body;assert.equal((await all(nativeFetchBody.pipeThrough(new env.TextDecoderStream()))).join(''),'native 中文 😀');
  const responseEncoder=new env.TextEncoderStream();const text=new Response(responseEncoder.readable).text();const responseWriter=responseEncoder.writable.getWriter();await responseWriter.write('response 中文');await responseWriter.close();assert.equal(await text,'response 中文');
  const bad=new env.TextDecoderStream('utf-8',{fatal:true}),badRead=all(bad.readable);badRead.catch(()=>{});const badWriter=bad.writable.getWriter();await assert.rejects(badWriter.write(new Uint8Array([255])));await assert.rejects(badRead);
  const cancelled=new env.TextEncoderStream();const cancelWriter=cancelled.writable.getWriter();cancelWriter.closed.catch(()=>{});await cancelled.readable.cancel('fixture cancel');await assert.rejects(cancelWriter.closed);
  const saved={encoder:env.TextEncoderStream,decoder:env.TextDecoderStream,transform:env.TransformStream,pipe:ReadableStream.prototype.pipeThrough};vm.runInNewContext(source,env);assert.equal(env.TextEncoderStream,saved.encoder);assert.equal(env.TextDecoderStream,saved.decoder);assert.equal(ReadableStream.prototype.pipeThrough,saved.pipe);
  const modern={TextEncoderStream,TextDecoderStream,ReadableStream,WritableStream,TransformStream};modern.window=modern;vm.runInNewContext(source,modern);assert.equal(modern.TransformStream,TransformStream);assert.equal(modern.TextEncoderStream,TextEncoderStream);
  console.log(JSON.stringify({split_surrogates_and_utf8:true,split_multibyte_decoding:true,native_fetch_body_pipeline:true,native_response_body:true,fatal_decode_errors:true,cancellation:true,idempotent:true,modern_native_classes_preserved:true}));
}finally{for(const [key,value]of Object.entries(descriptors))Object.defineProperty(ReadableStream.prototype,key,value);}
