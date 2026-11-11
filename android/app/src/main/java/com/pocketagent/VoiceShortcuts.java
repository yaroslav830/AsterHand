package com.pocketagent;

import android.content.Context;
import android.content.Intent;
import android.content.pm.ShortcutInfo;
import android.content.pm.ShortcutManager;
import android.graphics.drawable.Icon;
import android.net.Uri;
import android.os.Build;
import java.util.Collections;

/** Android launcher entry; microphone permission is still checked by VoiceController. */
public final class VoiceShortcuts {
    private static final String ID = "asterhand.voice";
    private VoiceShortcuts() {}

    /** Adds a launcher long-press shortcut without replacing unrelated app shortcuts. */
    public static boolean install(Context context) {
        if (context == null || Build.VERSION.SDK_INT < 25) return false;
        Context app = context.getApplicationContext();
        try {
            ShortcutManager manager = app.getSystemService(ShortcutManager.class);
            if (manager == null || manager.isRateLimitingActive()) return false;
            return manager.addDynamicShortcuts(Collections.singletonList(shortcut(app)));
        } catch (RuntimeException unavailable) { return false; }
    }

    /** Call only from an explicit user action; the launcher asks before pinning. */
    public static boolean requestPin(Context context) {
        if (context == null || Build.VERSION.SDK_INT < 26) return false;
        Context app = context.getApplicationContext();
        try {
            ShortcutManager manager = app.getSystemService(ShortcutManager.class);
            return manager != null && manager.isRequestPinShortcutSupported()
                    && manager.requestPinShortcut(shortcut(app), null);
        } catch (RuntimeException unavailable) { return false; }
    }

    private static ShortcutInfo shortcut(Context context) {
        Intent intent = new Intent(Intent.ACTION_VIEW, Uri.parse("asterhand://voice"))
                .setClass(context, MainActivity.class)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        ShortcutInfo.Builder builder = new ShortcutInfo.Builder(context, ID)
                .setShortLabel("语音对话").setLongLabel("和 AsterHand 连续对话").setIntent(intent);
        int icon = context.getApplicationInfo().icon;
        if (icon != 0) builder.setIcon(Icon.createWithResource(context, icon));
        return builder.build();
    }
}
