package com.pocketagent;
public final class InputTextPolicyTest {
    private static int checks;
    private static void check(boolean value){if(!value)throw new AssertionError("Input text policy check "+checks);checks++;}
    public static void main(String[] args){
        InputTextPolicy.Plan p=InputTextPolicy.plan("热门推荐",true,0,0,"方大同 红豆",false);check(p.value.equals("方大同 红豆"));check(p.hintIgnored);
        p=InputTextPolicy.plan("原内容",false,3,3,"追加",false);check(p.value.equals("原内容追加"));check(p.selectionUsed);
        p=InputTextPolicy.plan("abcd",false,1,3,"中文",false);check(p.value.equals("a中文d"));check(p.cursor==3);
        p=InputTextPolicy.plan("abcd",false,3,1,"中文",false);check(p.value.equals("a中文d"));
        p=InputTextPolicy.plan("热门推荐",false,4,4,"！",false);check(p.value.equals("热门推荐！"));
        p=InputTextPolicy.plan("旧搜索",false,3,3,"新搜索",true);check(p.value.equals("新搜索"));
        p=InputTextPolicy.plan("新搜索",false,3,3,"新搜索",true);check(p.value.equals("新搜索"));
        p=InputTextPolicy.plan("未知可能是提示",false,-1,-1,"确切内容",false);check(p.value.equals("确切内容"));
        p=InputTextPolicy.plan("原内容",false,3,3,"",true);check(p.value.isEmpty());
        p=InputTextPolicy.plan(null,false,0,0,"文本",false);check(p.value.equals("文本"));
        System.out.println("Input text policy fixtures passed: "+checks+" (no device or input actions)");
    }
}
