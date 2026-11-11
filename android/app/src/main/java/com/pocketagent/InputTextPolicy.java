package com.pocketagent;

/** Text only: no Android API or heuristic based on the words/color of a hint. */
final class InputTextPolicy {
    static final class Plan {
        final String value;final int cursor;final boolean hintIgnored,selectionUsed;
        Plan(String value,int cursor,boolean hint,boolean selection){this.value=value;this.cursor=cursor;hintIgnored=hint;selectionUsed=selection;}
    }
    static Plan plan(String current,boolean showingHint,int start,int end,String input,boolean replace){
        String old=showingHint?"":current==null?"":current;String text=input==null?"":input;
        if(replace||showingHint)return new Plan(text,text.length(),showingHint,false);
        if(start<0||end<0||start>old.length()||end>old.length())return new Plan(text,text.length(),false,false);
        int left=Math.min(start,end),right=Math.max(start,end);
        return new Plan(old.substring(0,left)+text+old.substring(right),left+text.length(),false,true);
    }
}
