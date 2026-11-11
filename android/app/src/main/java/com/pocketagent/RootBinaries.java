package com.pocketagent;

import java.io.File;
import java.io.IOException;

final class RootBinaries {
    private static final String[] CANDIDATES={"/product/bin/su","/system/bin/su","/system/xbin/su","/sbin/su","/debug_ramdisk/su","/su/bin/su","/data/adb/magisk/su"};
    static String su()throws IOException{
        for(String path:CANDIDATES){File file=new File(path);if(file.isFile()&&file.canExecute())return path;}
        throw new IOException("没有可执行的 su；请检查本应用的 Root 管理器授权。");
    }
}
