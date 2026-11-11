package com.pocketagent;

/** Pure display-coordinate layout; independent of changing small-window IME intersections. */
final class OverlayGeometry {
    static final class Panel {
        final int x,y,width,height;final String side;
        Panel(int x,int y,int width,int height,String side){this.x=x;this.y=y;this.width=width;this.height=height;this.side=side;}
    }
    static int imeHeight(boolean visible,int observed,int cached){return !visible?0:observed>0?observed:Math.max(0,cached);}
    static Panel panel(int screenWidth,int screenHeight,int top,int bubbleX,int bubbleY,int bubbleWidth,int bubbleHeight,int desiredWidth,int desiredHeight,int gap,int margin,int minHeight,int imeHeight,String previousSide,boolean choose){
        int bottom=Math.max(top+1,screenHeight-Math.max(0,imeHeight)-margin);
        int above=Math.min(bubbleY-gap,bottom)-top,below=bottom-(bubbleY+bubbleHeight+gap);
        String side=previousSide==null?"below":previousSide;
        if(choose||imeHeight>0)side=below>=desiredHeight-gap*2||below>=above?"below":"above";
        int room="below".equals(side)?below:above;
        if(room<minHeight){side="below".equals(side)?"above":"below";room="below".equals(side)?below:above;}
        int width=Math.max(1,Math.min(desiredWidth,screenWidth-margin*2));
        int height=Math.max(1,Math.min(desiredHeight,Math.min(bottom-top,Math.max(minHeight,room))));
        int x=Math.max(margin,Math.min(screenWidth-width-margin,bubbleX+bubbleWidth-width));
        int anchor="below".equals(side)?bubbleY+bubbleHeight+gap:bubbleY-gap-height;
        int y=Math.max(top,Math.min(anchor,bottom-height));
        return new Panel(x,y,width,height,side);
    }
}
