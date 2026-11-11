// Loaded only inside the ephemeral login page. Preserve existing browser APIs.
// Streams read only what the page explicitly writes/pipes; nothing is logged.
(function (window, streams) {
  'use strict';
  var NativeReadable = window.ReadableStream;
  function bridge(source, StreamClass, acquire) {
    var reader = acquire ? source.getReader() : null, ended = false;
    function release() {
      ended = true;
      if (reader) { try { reader.releaseLock(); } catch (_) {} }
      reader = null;
    }
    var stream = new StreamClass({
      pull: function(controller) {
        if (ended) return;
        if (!reader) reader = source.getReader();
        return reader.read().then(function(result) {
          if (ended) return;
          if (result.done) { controller.close(); release(); } else controller.enqueue(result.value);
        }, function(error) { if (!ended) { controller.error(error); release(); } });
      },
      cancel: function(reason) {
        if (ended) return;
        if (!reader) reader = source.getReader();
        return Promise.resolve(reader.cancel(reason)).then(release, function(error) { release(); throw error; });
      }
    }, {highWaterMark:0});
    return {stream:stream, release:release};
  }
  if (typeof window.TransformStream !== 'function') {
    var transforms = new WeakMap();
    function CompatibleTransformStream(transformer, writableStrategy, readableStrategy) {
      if (!(this instanceof CompatibleTransformStream)) throw new TypeError('TransformStream requires new');
      var inner = new streams.TransformStream(transformer, writableStrategy, readableStrategy);
      var readable = typeof NativeReadable === 'function' ? bridge(inner.readable, NativeReadable, false).stream : inner.readable;
      transforms.set(this, {readable:readable, writable:inner.writable});
    }
    Object.defineProperties(CompatibleTransformStream.prototype, {
      readable:{get:function(){ if(!transforms.has(this))throw new TypeError('Invalid TransformStream');return transforms.get(this).readable; }},
      writable:{get:function(){ if(!transforms.has(this))throw new TypeError('Invalid TransformStream');return transforms.get(this).writable; }}
    });
    window.TransformStream = CompatibleTransformStream;
    if (typeof window.WritableStream !== 'function') window.WritableStream = streams.WritableStream;
    if (typeof NativeReadable !== 'function') window.ReadableStream = streams.ReadableStream;
    else {
      // Old Safari fetch() still returns native readable streams. Adapt only a
      // pipe whose destination is the bundled writable implementation.
      var nativePipeTo = NativeReadable.prototype.pipeTo, nativePipeThrough = NativeReadable.prototype.pipeThrough;
      Object.defineProperty(NativeReadable.prototype, 'pipeTo', {configurable:true,writable:true,value:function(destination,options){
        if (!(destination instanceof streams.WritableStream) && typeof nativePipeTo === 'function') return nativePipeTo.call(this,destination,options);
        var adapted;
        try { adapted=bridge(this,streams.ReadableStream,true); }
        catch(error) { return Promise.reject(error); }
        return adapted.stream.pipeTo(destination,options).then(function(){adapted.release();},function(error){adapted.release();throw error;});
      }});
      Object.defineProperty(NativeReadable.prototype, 'pipeThrough', {configurable:true,writable:true,value:function(pair,options){
        if ((!pair || !(pair.writable instanceof streams.WritableStream)) && typeof nativePipeThrough === 'function') return nativePipeThrough.call(this,pair,options);
        if(!pair || !pair.readable || typeof pair.readable.getReader!=='function' || !pair.writable || this.locked || pair.writable.locked)throw new TypeError('Invalid or locked stream pair');
        var piping=this.pipeTo(pair.writable,options);piping.catch(function(){});return pair.readable;
      }});
    }
  }
  var encoders=new WeakMap(),decoders=new WeakMap();
  function store(map,instance){if(!map.has(instance))throw new TypeError('Invalid encoding stream');return map.get(instance);}
  function streamProperties(type,map,extras){
    var properties={readable:{get:function(){return store(map,this).stream.readable;}},writable:{get:function(){return store(map,this).stream.writable;}}};
    Object.keys(extras).forEach(function(key){properties[key]={get:function(){return extras[key](store(map,this));}};});
    Object.defineProperties(type.prototype,properties);
  }
  if (typeof window.TextEncoderStream !== 'function' && typeof window.TextEncoder === 'function') {
    function CompatibleTextEncoderStream() {
      if(!(this instanceof CompatibleTextEncoderStream))throw new TypeError('TextEncoderStream requires new');
      var encoder=new window.TextEncoder(),pending='';
      var stream=new window.TransformStream({
        transform:function(chunk,controller){
          if(typeof chunk==='symbol')throw new TypeError('Cannot encode Symbol');
          var text=pending+String(chunk);pending='';
          if(text.length){var last=text.charCodeAt(text.length-1);if(last>=0xD800&&last<=0xDBFF){pending=text.slice(-1);text=text.slice(0,-1);}}
          var bytes=encoder.encode(text);if(bytes.length)controller.enqueue(bytes);
        },
        flush:function(controller){if(pending)controller.enqueue(encoder.encode(pending));}
      });
      encoders.set(this,{stream:stream});
    }
    streamProperties(CompatibleTextEncoderStream,encoders,{encoding:function(){return 'utf-8';}});
    window.TextEncoderStream=CompatibleTextEncoderStream;
  }
  if (typeof window.TextDecoderStream !== 'function' && typeof window.TextDecoder === 'function') {
    function CompatibleTextDecoderStream(label,options) {
      if(!(this instanceof CompatibleTextDecoderStream))throw new TypeError('TextDecoderStream requires new');
      var decoder=new window.TextDecoder(label,options);
      var stream=new window.TransformStream({
        transform:function(chunk,controller){var text=decoder.decode(chunk,{stream:true});if(text)controller.enqueue(text);},
        flush:function(controller){var text=decoder.decode();if(text)controller.enqueue(text);}
      });
      decoders.set(this,{stream:stream,decoder:decoder});
    }
    streamProperties(CompatibleTextDecoderStream,decoders,{encoding:function(s){return s.decoder.encoding;},fatal:function(s){return s.decoder.fatal;},ignoreBOM:function(s){return s.decoder.ignoreBOM;}});
    window.TextDecoderStream=CompatibleTextDecoderStream;
  }
})(window, module.exports);
