/* Generated catalogs are appended by sync_localizations.py. No network is used. */
(function (root) {
  'use strict';
  var languages = ['system', 'zh-CN', 'en', 'ja', 'es', 'fr'];
  var preference = 'system';
  var patterns;
  var tokenPattern = /%(?:\d+\$)?[-+0 #]*(?:\d+)?(?:\.\d+)?(?:ll|l)?[@diuf]|\{[a-zA-Z0-9_]+\}/g;
  var prefixes=['正在连接 ','正在操作 · ','命令退出 ','保存项目失败：','无法读取项目记录，原文件已保留：','导出失败：','保存对话失败：','未知屏幕工具：','未知文件工具：','系统输入执行失败：','模型响应未完成：','Claude 响应未完成：','DeepSeek 响应未完成：','OpenAI 未完成授权：','模型列表 HTTP ','正在'];
  var suffixes=[' · 已返回结果',' 秒无回应已结束语音','，正在重试',' 希望连接这台设备'];
  function dynamic(source, language) {
    if (!patterns) {
      patterns = [];
      Object.keys(root.AsterI18nCatalog.messages).forEach(function (key) {
        var tokens = key.match(tokenPattern);
        if (!tokens || key.length > 2048) return;
        var pieces = key.split(tokenPattern);
        var expression = pieces.map(function (piece) { return piece.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'); }).join('([\\s\\S]+?)');
        patterns.push({expression:new RegExp('^' + expression + '$'), key:key, tokens:tokens});
      });
    }
    for (var i = 0; i < patterns.length; i++) {
      var pattern = patterns[i], match = source.match(pattern.expression);
      if (!match) continue;
      var entry = root.AsterI18nCatalog.messages[pattern.key], index = 0;
      return (entry[language] || entry.en).replace(tokenPattern, function () { return match[++index]; });
    }
    for (var j=0;j<prefixes.length;j++) if(source.indexOf(prefixes[j])===0&&source.length>prefixes[j].length) return t(prefixes[j])+source.slice(prefixes[j].length);
    for (var k=0;k<suffixes.length;k++) if(source.slice(-suffixes[k].length)===suffixes[k]&&source.length>suffixes[k].length) return source.slice(0,-suffixes[k].length)+t(suffixes[k]);
    var separator=source.indexOf('：');
    if(separator>0&&root.AsterI18nCatalog.messages[source.slice(separator+1)])return source.slice(0,separator)+': '+t(source.slice(separator+1));
    return source;
  }
  var systemLanguages = (root.navigator && (root.navigator.languages || [root.navigator.language])) || ['en'];
  function resolve(values) {
    for (var i = 0; i < values.length; i++) {
      var base = String(values[i] || '').replace(/_/g, '-').toLowerCase().split('-')[0];
      if (base === 'zh') return 'zh-CN';
      if (['en', 'ja', 'es', 'fr'].indexOf(base) >= 0) return base;
    }
    return 'en';
  }
  function locale() { return preference === 'system' ? resolve(systemLanguages) : preference; }
  function t(source, values) {
    var messages = root.AsterI18nCatalog.messages, language = locale(), entry = messages[source];
    if (source == null) return source;
    var result = language === 'zh-CN' ? source : entry && (entry[language] || entry.en) || (typeof source === 'string' && source.length <= 8192 ? dynamic(source, language) : source);
    return values ? result.replace(/\{([a-zA-Z0-9_]+)\}/g, function (match, key) {
      return Object.prototype.hasOwnProperty.call(values, key) ? String(values[key]) : match;
    }) : result;
  }
  function setLanguage(value, preferred) {
    preference = languages.indexOf(value) >= 0 ? value : 'system';
    if (preferred && preferred.length) systemLanguages = preferred;
    if (root.document) root.document.documentElement.lang = locale();
  }
  function name(value) {
    return {system:t('跟随系统'), 'zh-CN':'简体中文', en:'English', ja:'日本語', es:'Español', fr:'Français'}[value] || 'English';
  }
  // Only explicitly marked UI nodes and attributes are translated. User text is untouched.
  function apply(container) {
    var nodes = container.querySelectorAll('[data-i18n], [data-i18n-attrs]');
    for (var i = 0; i < nodes.length; i++) {
      var node = nodes[i], key = node.getAttribute('data-i18n');
      if (key !== null) node.textContent = t(key);
      var attributes = (node.getAttribute('data-i18n-attrs') || '').split(' ');
      for (var j = 0; j < attributes.length; j++) if (attributes[j]) {
        var attribute = attributes[j];
        node.setAttribute(attribute, t(node.getAttribute('data-i18n-' + attribute)));
      }
    }
  }
  root.AsterI18n = {t:t, locale:locale, setLanguage:setLanguage, languages:languages, name:name, apply:apply, resolve:resolve};
})(typeof window === 'undefined' ? globalThis : window);
