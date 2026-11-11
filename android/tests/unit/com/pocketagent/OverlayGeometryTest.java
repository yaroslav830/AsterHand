package com.pocketagent;
public final class OverlayGeometryTest {
    private static int checks;
    private static void check(boolean value,String label){if(!value)throw new AssertionError(label);checks++;}
    private static OverlayGeometry.Panel place(int w,int h,int bx,int by,int ime){return OverlayGeometry.panel(w,h,60,bx,by,56,56,344,420,12,12,96,ime,"below",true);}
    public static void main(String[] args){
        OverlayGeometry.Panel high=place(411,914,330,120,0);check(high.side.equals("below")&&high.y==188,"normal below keeps fixed gap");
        OverlayGeometry.Panel low=place(411,914,330,650,0);check(low.side.equals("above")&&low.y+low.height==638,"normal above keeps fixed gap");
        OverlayGeometry.Panel before=place(411,914,330,416,0);check(before.side.equals("below"),"regression: lower anchor initially opens below");
        OverlayGeometry.Panel keyboard=place(411,914,330,416,364);check(keyboard.side.equals("above")&&keyboard.y>=60&&keyboard.y+keyboard.height<=538,"IME moves panel into usable area");
        check(keyboard.y+keyboard.height==404,"IME fits above with same gap when possible");
        int cached=OverlayGeometry.imeHeight(true,364,0);cached=OverlayGeometry.imeHeight(true,0,cached);check(cached==364,"moving above IME must not zero its global height");
        OverlayGeometry.Panel stable=place(411,914,330,416,cached);check(stable.y==keyboard.y&&stable.height==keyboard.height,"repeated zero intersection cannot oscillate geometry");
        cached=OverlayGeometry.imeHeight(false,0,cached);OverlayGeometry.Panel restored=place(411,914,330,416,cached);check(cached==0&&restored.y==before.y&&restored.height==before.height,"keyboard close restores original anchor layout");
        OverlayGeometry.Panel landscape=place(914,411,820,180,150);check(landscape.y>=60&&landscape.y+landscape.height<=249,"landscape avoids IME");
        OverlayGeometry.Panel narrow=place(240,640,190,100,0);check(narrow.x>=12&&narrow.x+narrow.width<=228,"narrow window stays inside horizontal margins");
        OverlayGeometry.Panel belowIme=place(411,914,330,800,364);check(belowIme.y>=60&&belowIme.y+belowIme.height<=538,"off-usable-area bubble cannot drag panel below IME");
        OverlayGeometry.Panel tiny=place(411,200,330,100,180);check(tiny.height>0&&tiny.y>=60,"extreme keyboard leaves bounded nonnegative geometry");
        System.out.println("{\"fixture\":true,\"checks\":"+checks+",\"phone_used\":false,\"success\":true}");
    }
}
