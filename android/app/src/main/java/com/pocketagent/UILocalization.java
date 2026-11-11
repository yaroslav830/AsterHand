package com.pocketagent;

import android.content.Context;
import android.os.Build;
import org.json.JSONObject;
import org.json.JSONArray;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.util.Arrays;
import java.util.Locale;

/** Offline UI translations. Never applied to stored messages, commands or protocol tokens. */
public final class UILocalization {
    private static Context app;
    private static JSONObject messages = new JSONObject();
    private static final java.util.regex.Pattern TOKEN = java.util.regex.Pattern.compile("%(?:[0-9]+\\$)?[-+0 #]*(?:[0-9]+)?(?:\\.[0-9]+)?(?:ll|l)?[@diuf]|\\{[a-zA-Z0-9_]+\\}");
    private static final java.util.List<String> templateKeys = new java.util.ArrayList<>();
    private static final java.util.List<java.util.regex.Pattern> templates = new java.util.ArrayList<>();
    public static final String[] LANGUAGES = {"system", "zh-CN", "en", "ja", "es", "fr"};
    private UILocalization() {}
    public static synchronized void initialize(Context context) {
        if (app != null) return;
        app = context.getApplicationContext();
        try (InputStream in = app.getAssets().open("localizations.json")) {
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            byte[] buffer = new byte[8192]; int count;
            while ((count = in.read(buffer)) != -1) out.write(buffer, 0, count);
            messages = new JSONObject(new String(out.toByteArray(), "UTF-8")).getJSONObject("messages");
            java.util.Iterator<String> keys=messages.keys();
            while(keys.hasNext()) {String key=keys.next();java.util.regex.Matcher slots=TOKEN.matcher(key);StringBuilder expression=new StringBuilder("^");int offset=0,slotCount=0;
                while(slots.find()){expression.append(java.util.regex.Pattern.quote(key.substring(offset,slots.start()))).append("([\\s\\S]+?)");offset=slots.end();slotCount++;}
                if(slotCount>0&&key.length()<=2048){expression.append(java.util.regex.Pattern.quote(key.substring(offset))).append("$");templateKeys.add(key);templates.add(java.util.regex.Pattern.compile(expression.toString()));}
            }
        } catch (Exception ignored) { /* Source copy is the final fallback. */ }
    }
    public static boolean valid(String value) { return Arrays.asList(LANGUAGES).contains(value); }
    public static String preference() {
        String value = app == null ? "system" : app.getSharedPreferences("MainActivity", 0).getString("uiLanguage", "system");
        return valid(value) ? value : "system";
    }
    public static JSONArray systemLanguages(Context context) {
        JSONArray values = new JSONArray();
        android.content.res.Configuration config = context.getResources().getConfiguration();
        if (Build.VERSION.SDK_INT >= 24) {
            for (int i = 0; i < config.getLocales().size(); i++) values.put(config.getLocales().get(i).toLanguageTag());
        } else values.put(config.locale.toLanguageTag());
        return values;
    }
    public static String language() {
        String value = preference();
        if (!value.equals("system")) return value;
        JSONArray values = app == null ? new JSONArray().put(Locale.getDefault().toLanguageTag()) : systemLanguages(app);
        for (int i = 0; i < values.length(); i++) {
            String base = values.optString(i).replace('_', '-').toLowerCase(Locale.ROOT).split("-")[0];
            if (base.equals("zh")) return "zh-CN";
            if (Arrays.asList("en", "ja", "es", "fr").contains(base)) return base;
        }
        return "en";
    }
    public static String t(String source) {
        if (source == null || language().equals("zh-CN")) return source;
        JSONObject entry = messages.optJSONObject(source);
        if(entry!=null)return entry.optString(language(), entry.optString("en", source));
        if(source.length()<=8192)for(int i=0;i<templates.size();i++){java.util.regex.Matcher values=templates.get(i).matcher(source);if(!values.matches())continue;
            JSONObject item=messages.optJSONObject(templateKeys.get(i));String format=item.optString(language(),item.optString("en",source));java.util.regex.Matcher slots=TOKEN.matcher(format);StringBuffer result=new StringBuffer();int group=0;
            while(slots.find())slots.appendReplacement(result,java.util.regex.Matcher.quoteReplacement(values.group(++group)));slots.appendTail(result);return result.toString();}
        for(String prefix:new String[]{"正在连接 ","正在操作 · ","命令退出 ","保存项目失败：","无法读取项目记录，原文件已保留：","导出失败：","保存对话失败：","未知屏幕工具：","未知文件工具：","系统输入执行失败：","模型响应未完成：","Claude 响应未完成：","DeepSeek 响应未完成：","OpenAI 未完成授权：","模型列表 HTTP ","正在"})if(source.startsWith(prefix)&&source.length()>prefix.length())return t(prefix)+source.substring(prefix.length());
        for(String suffix:new String[]{" · 已返回结果"," 秒无回应已结束语音","，正在重试"," 希望连接这台设备"})if(source.endsWith(suffix)&&source.length()>suffix.length())return source.substring(0,source.length()-suffix.length())+t(suffix);
        int separator=source.indexOf('：');if(separator>0&&messages.has(source.substring(separator+1)))return source.substring(0,separator)+": "+t(source.substring(separator+1));
        return source;
    }
}
