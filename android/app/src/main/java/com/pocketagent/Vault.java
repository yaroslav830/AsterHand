package com.pocketagent;

import android.content.Context;
import android.content.SharedPreferences;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

final class Vault {
    private static final String ALIAS = "PocketAgent.KeyVault.v1";
    private final SharedPreferences prefs;
    Vault(Context context) { prefs = context.getSharedPreferences("vault", Context.MODE_PRIVATE); }
    private SecretKey key() throws Exception {
        KeyStore store = KeyStore.getInstance("AndroidKeyStore"); store.load(null);
        if (store.containsAlias(ALIAS)) return ((SecretKey) store.getKey(ALIAS, null));
        KeyGenerator generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
        generator.init(new KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT|KeyProperties.PURPOSE_DECRYPT).setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).setRandomizedEncryptionRequired(true).build());
        return generator.generateKey();
    }
    synchronized void put(String name, String value) throws Exception {
        if (value == null || value.isEmpty()) { prefs.edit().remove(name).apply(); return; }
        Cipher cipher=Cipher.getInstance("AES/GCM/NoPadding"); cipher.init(Cipher.ENCRYPT_MODE,key());
        byte[] iv=cipher.getIV(), encrypted=cipher.doFinal(value.getBytes(StandardCharsets.UTF_8));
        byte[] packed=new byte[iv.length+encrypted.length]; System.arraycopy(iv,0,packed,0,iv.length); System.arraycopy(encrypted,0,packed,iv.length,encrypted.length);
        prefs.edit().putString(name,Base64.encodeToString(packed,Base64.NO_WRAP)).apply();
    }
    synchronized String get(String name) {
        String value=prefs.getString(name,null); if(value==null)return "";
        try { byte[] packed=Base64.decode(value,Base64.NO_WRAP); Cipher cipher=Cipher.getInstance("AES/GCM/NoPadding"); cipher.init(Cipher.DECRYPT_MODE,key(),new GCMParameterSpec(128,packed,0,12)); return new String(cipher.doFinal(packed,12,packed.length-12),StandardCharsets.UTF_8); }
        catch(Exception e){return "";}
    }
    void remove(String name) { prefs.edit().remove(name).apply(); }
}
