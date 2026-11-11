// Run before the login page's first script on older WebKit versions.
// Diagnostics contain error categories, code identifiers, public JS asset locations
// and HTTP status numbers. No credentials, page contents, bodies or URL queries.
(function () {
  'use strict';
  var URLClass = window.URL;
  // Safari before 15.4 cannot propagate a nonce via CSP strict-dynamic.
  // Reuse the page's own nonce only for its exact official SDK loaders. Do not
  // change CSP, fetch or script contents, and never authorize arbitrary scripts.
  if(window.__asterHandLegacyCSP&&window.location&&window.location.hostname==='auth.openai.com'&&window.Node&&window.document){
    ['appendChild','insertBefore'].forEach(function(method){
      var original=window.Node.prototype[method];if(typeof original!=='function'||original.__asterHandNonce)return;
      var wrapped=function(node){
        if(node&&node.tagName==='SCRIPT'&&!node.nonce&&node.src){
          try{
            var target=new URLClass(node.src,window.location.href);
            if(target.protocol==='https:'&&!target.username&&!target.password&&!target.port&&!target.search&&!target.hash&&['sentinel.openai.com','chatgpt.com'].indexOf(target.hostname)>=0&&(/^\/backend-api\/sentinel\/sdk\.js$/.test(target.pathname)||/^\/sentinel\/[A-Za-z0-9_-]+\/sdk\.js$/.test(target.pathname))){
              var roots=window.document.querySelectorAll('script[nonce]'),nonce='';
              for(var i=0;i<roots.length;i++){
                var root=roots[i];if(!root.nonce)continue;
                if(root.src){var url=new URLClass(root.src,window.location.href);if(url.protocol!=='https:'||['auth.openai.com','auth-cdn.oaistatic.com'].indexOf(url.hostname)<0)continue;}
                nonce=root.nonce;break;
              }
              if(nonce){node.nonce=nonce;var health=window.__asterHandLoginHealth;if(health&&health.indexOf('legacy_script_nonce')<0&&health.length<80)health.push('legacy_script_nonce');}
            }
          }catch(_){}
        }
        return original.apply(this,arguments);
      };
      Object.defineProperty(wrapped,'__asterHandNonce',{value:true});
      Object.defineProperty(window.Node.prototype,method,{configurable:true,writable:true,value:wrapped});
    });
  }
  var legacyForms=window.Array&&typeof window.Array.prototype.at!=='function';
  if(window.Array&&typeof window.Array.prototype.at!=='function'){
    Object.defineProperty(window.Array.prototype,'at',{configurable:true,writable:true,value:function(index){
      if(this==null)throw new TypeError('Array receiver required');
      var object=Object(this),length=Math.min(Math.max(Math.trunc(+object.length)||0,0),9007199254740991);
      var relative=Math.trunc(+index)||0,key=relative>=0?relative:length+relative;
      return key<0||key>=length?undefined:object[key];
    }});
  }
  if (typeof URLClass === 'function' && typeof URLClass.canParse !== 'function') {
    Object.defineProperty(URLClass, 'canParse', { configurable: true, writable: true, value: function (input, base) {
      try { if (arguments.length === 0) throw new TypeError('URL input is required'); new URLClass(input, base); return true; } catch (_) { return false; }
    }});
  }
  if (typeof URLClass === 'function' && typeof URLClass.parse !== 'function') {
    Object.defineProperty(URLClass, 'parse', { configurable: true, writable: true, value: function (input, base) {
      try { if (arguments.length === 0) return null; return new URLClass(input, base); } catch (_) { return null; }
    }});
  }
  var performance = window.performance;
  if (performance && typeof performance.getEntriesByName === 'function') {
    // Old User Timing implementations create entries but return undefined.
    // Return the actual entry, as Level 3 requires, without inventing timings.
    ['mark','measure'].forEach(function(method) {
      var original=performance[method],clear=performance[method==='mark'?'clearMarks':'clearMeasures'];
      if(typeof original!=='function'||typeof clear!=='function')return;
      var probe='__asterHandTimingProbe_'+method,legacy=false;
      try {legacy=original.call(performance,probe)===undefined;} finally {clear.call(performance,probe);}
      if(!legacy)return;
      Object.defineProperty(performance,method,{configurable:true,writable:true,value:function(name){
        if(typeof name==='symbol')throw new TypeError('Timing name cannot be a Symbol');
        var args=Array.prototype.slice.call(arguments);if(args.length)args[0]=String(name);
        var result=original.apply(this,args);
        if(result!==undefined)return result;
        var entries=this.getEntriesByName(args[0],method),entry=entries[entries.length-1];
        if(entry&&window.__asterHandLoginHealth&&window.__asterHandLoginHealth.indexOf('legacy_user_timing_return')===-1&&window.__asterHandLoginHealth.length<80)window.__asterHandLoginHealth.push('legacy_user_timing_return');
        return entry;
      }});
    });
  }
  if (!window.__asterHandLoginHealth) {
    var events = [];
    Object.defineProperty(window, '__asterHandLoginHealth', {value: events});
    function record(value) { if (events.length < 80) events.push(value); }
    if(legacyForms&&window.document){
      // Old WebKit omits SubmitEvent.submitter. React Router needs the actual
      // clicked button to include its name/value in the original form request.
      var clicked=null;
      window.document.addEventListener('click',function(event){
        clicked=null;if(!event.isTrusted)return;
        var node=event.target;while(node&&node!==window.document){if((node.tagName==='BUTTON'||node.tagName==='INPUT')&&node.form&&node.type==='submit'&&!node.disabled){clicked={button:node,time:Date.now()};break;}node=node.parentNode;}
      },true);
      window.document.addEventListener('submit',function(event){
        var previous=clicked;clicked=null;
        if(event.isTrusted&&!event.submitter&&previous&&Date.now()-previous.time<1500&&previous.button.form===event.target&&!previous.button.disabled){Object.defineProperty(event,'submitter',{configurable:true,value:previous.button});record('legacy_form_submitter');}
      },true);
    }
    function issue(error, filename, line, column) {
      var name = error && error.name, message = String(error && error.message || '');
      var kind = ({ReferenceError:'reference',TypeError:'type',SyntaxError:'syntax',NetworkError:'network',SecurityError:'security',AbortError:'abort'})[name] || 'unknown';
      record('web_' + kind + '_error');
      if (/importing (a )?module script failed/i.test(message)) record('web_module_import_failed');
      if (/assign to read.?only|only a getter/i.test(message)) record('web_readonly_assignment');
      if (/illegal invocation|incompatible receiver/i.test(message)) record('web_invalid_receiver');
      // Record code identifiers only, never exception values, page text or inputs.
      var identifier = name === 'ReferenceError' && (message.match(/Can't find variable:\s*([A-Za-z_$][A-Za-z0-9_$]{0,48})\b/) || message.match(/^([A-Za-z_$][A-Za-z0-9_$]{0,48}) is not defined\b/));
      if (identifier) record('js_reference_' + identifier[1].toLowerCase().replace(/\$/g, '_'));
      var method = name === 'TypeError' && message.match(/\.([A-Za-z_$][A-Za-z0-9_$]{0,48})\s*\(/);
      if (method) record('js_method_' + method[1].toLowerCase().replace(/\$/g, '_'));
      var expression = name === 'TypeError' && message.match(/(?:evaluating|near) '([A-Za-z_$][A-Za-z0-9_$.[\]() ]{0,65})'/);
      if (expression) record('js_expression_' + expression[1].toLowerCase().replace(/[^a-z0-9_]/g, '_'));
      var stack=String(error&&error.stack||''),asset=stack.match(/https:\/\/(auth\.openai\.com|cdn\.oaistatic\.com|auth-cdn\.oaistatic\.com)\/([A-Za-z0-9_./-]+\.js)(?:\?[^: ()]*)?:(\d+):(\d+)/);
      if(!asset&&filename){var direct=String(filename).match(/^https:\/\/(auth\.openai\.com|cdn\.oaistatic\.com|auth-cdn\.oaistatic\.com)\/([A-Za-z0-9_./-]+\.js)(?:\?[^#]*)?$/);if(direct)asset=[null,direct[1],direct[2],String(line||0),String(column||0)];}
      if(asset){var encoded=asset[2].replace(/[_/.]/g,function(c){return c==='_'?'_u_':c==='/'?'_s_':'_d_';});if(encoded.length<140)record('js_asset_'+(asset[1]==='auth.openai.com'?'auth_':asset[1]==='auth-cdn.oaistatic.com'?'authcdn_':'static_')+encoded+'_line_'+asset[3]+'_column_'+asset[4]);}
      else record(stack?'js_stack_unmapped':'js_stack_missing');
      var features = [['URL.parse','url_parse'],['withResolvers','promise_resolvers'],['structuredClone','structured_clone'],['toSorted','array_sorted'],['toReversed','array_reversed'],['findLast','array_last'],['hasOwn','object_hasown'],['randomUUID','crypto_uuid'],['union','set_union'],['AbortSignal.timeout','abort_timeout'],['AbortSignal.any','abort_any']];
      features.forEach(function(pair) { if (message.indexOf(pair[0]) !== -1) record('missing_' + pair[1]); });
    }
    if (typeof window.addEventListener === 'function') {
      window.addEventListener('error', function(event) {
        if(event.target&&event.target.tagName==='SCRIPT'){
          var host='other';try{var name=new URLClass(event.target.src,window.location.href).hostname;host=({'auth.openai.com':'auth','auth-cdn.oaistatic.com':'authcdn','sentinel.openai.com':'sentinel','chatgpt.com':'chatgpt'})[name]||'other';}catch(_){}
          record('script_load_failed_'+host);
        }else if(event.error)issue(event.error,event.filename,event.lineno,event.colno);else if(event.message==='Script error.')record('web_cross_origin_error');
      },true);
      window.addEventListener('unhandledrejection', function(event) { issue(event.reason); });
      window.addEventListener('securitypolicyviolation',function(event){
        if(event.disposition==='report')return;
        if(event.effectiveDirective==='script-src'||event.effectiveDirective==='script-src-elem'){var category='other';try{var host=new URLClass(event.blockedURI).hostname;category=({'sentinel.openai.com':'sentinel','chatgpt.com':'chatgpt','auth-cdn.oaistatic.com':'authcdn'})[host]||'other';}catch(_){}record('csp_script_blocked_'+category);}
      });
    }
    function hydrationState(){
      if(window.__loginWebSentinelSdkPrimaryError)record('login_sdk_primary_failed');
      var sdk=window.SentinelSDK,loads=window.__sentinel_script_loads;
      if(loads&&loads.attempts&&loads.attempts.length&&loads.attempts.every(function(a){return a.state==='failed';}))record('login_sdk_all_failed');
      if(sdk&&typeof sdk.init==='function'&&(!loads||sdk.init!==loads.stubInit))record('login_sdk_ready');
      // React may catch a startup exception and render its public stack instead
      // of dispatching window.error. Inspect only that explicit error page.
      if(window.document){var heading=window.document.querySelector('h1'),pre=window.document.querySelector('pre');if(heading&&heading.textContent==='Application Error'&&pre&&!window.__asterHandBoundaryRecorded){window.__asterHandBoundaryRecorded=true;issue({name:'TypeError',message:'',stack:pre.textContent});}}
      if(!window.document||!window.document.querySelector('input[type="email"]'))return;
      var button=window.document.querySelector('button');
      if(button)record(Object.keys(button).some(function(key){return key.indexOf('__reactProps$')===0;})?'react_hydrated':'react_not_hydrated');
    }
    if (typeof window.setTimeout === 'function') [2500,8000,20000].forEach(function(delay){window.setTimeout(hydrationState,delay);});
    if (typeof window.fetch === 'function') {
      var originalFetch = window.fetch;
      window.fetch = function(input, options) {
        var observe = false, method = 'other';
        try {
          var target = new URLClass(typeof input === 'string' ? input : input.url, window.location.href);
          observe = target.protocol === 'https:' && target.hostname === 'auth.openai.com' && target.pathname.indexOf('/api/accounts/') === 0;
          var verb = String(options && options.method || input && input.method || 'GET').toLowerCase();
          if (verb === 'get' || verb === 'post') method = verb;
        } catch (_) {}
        var result = originalFetch.apply(this, arguments);
        if (!observe) return result;
        return result.then(function(response) { record('fetch_' + method + '_' + response.status); return response; }, function(error) { record('fetch_' + method + '_failed'); issue(error); throw error; });
      };
    }
  }
})();
