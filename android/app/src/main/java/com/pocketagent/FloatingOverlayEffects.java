package com.pocketagent;
import android.content.Context;
import android.graphics.*;
import android.os.*;
import android.view.*;
import java.util.*;
/** A wholly noninteractive surface; its host window must have NOT_TOUCHABLE and safe opacity. */
final class FloatingOverlayEffects extends View {
    private final Paint paint=new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Path border=new Path(),trail=new Path();
    private final Matrix rotate=new Matrix();
    private boolean edge;
    private float width,opacity;
    private long gestureAt;
    private float x,y,x2,y2;
    private boolean swipe;
    FloatingOverlayEffects(Context context){super(context);setFocusable(false);setClickable(false);setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);setBackgroundColor(Color.TRANSPARENT);}
    void configure(boolean edge,float width,float opacity){this.edge=edge;this.width=width;this.opacity=opacity;invalidate();}
    void gesture(boolean swipe,float x,float y,float x2,float y2){this.swipe=swipe;this.x=x;this.y=y;this.x2=x2;this.y2=y2;gestureAt=SystemClock.uptimeMillis();invalidate();}
    boolean active(){return edge||(gestureAt!=0&&SystemClock.uptimeMillis()-gestureAt<1000);}
    private float dp(float n){return getResources().getDisplayMetrics().density*n;}
    private float systemRadius(){int id=getResources().getIdentifier("rounded_corner_radius","dimen","android");try{return id==0?0:getResources().getDimension(id);}catch(Exception e){return 0;}}
    private float radius(int position,float fallback){if(Build.VERSION.SDK_INT>=31){WindowInsets insets=getRootWindowInsets();RoundedCorner c=insets==null?null:insets.getRoundedCorner(position);if(c!=null)return c.getRadius();}return fallback;}
    private void borderPath(float inset){float w=getWidth(),h=getHeight(),fallback=systemRadius();float tl=radius(0,fallback),tr=radius(1,fallback),br=radius(2,fallback),bl=radius(3,fallback);tl=Math.max(0,tl-inset);tr=Math.max(0,tr-inset);br=Math.max(0,br-inset);bl=Math.max(0,bl-inset);Rect notch=null;if(Build.VERSION.SDK_INT>=28){WindowInsets insets=getRootWindowInsets();DisplayCutout cut=insets==null?null:insets.getDisplayCutout();if(cut!=null)for(Rect r:cut.getBoundingRects())if(r.top<=dp(6)&&r.width()>w*.25&&r.height()>dp(8)){notch=r;break;}}
        border.reset();if(notch==null){border.addRoundRect(new RectF(inset,inset,w-inset,h-inset),new float[]{tl,tl,tr,tr,br,br,bl,bl},Path.Direction.CW);return;}
        float left=Math.max(inset+tl,notch.left-inset),right=Math.min(w-inset-tr,notch.right+inset),bottom=notch.bottom+inset,r=Math.min(dp(12),Math.max(dp(3),bottom/3));border.moveTo(inset+tl,inset);border.lineTo(left-r,inset);border.quadTo(left,inset,left,inset+r);border.lineTo(left,bottom-r);border.quadTo(left,bottom,left+r,bottom);border.lineTo(right-r,bottom);border.quadTo(right,bottom,right,bottom-r);border.lineTo(right,inset+r);border.quadTo(right,inset,right+r,inset);border.lineTo(w-inset-tr,inset);border.quadTo(w-inset,inset,w-inset,inset+tr);border.lineTo(w-inset,h-inset-br);border.quadTo(w-inset,h-inset,w-inset-br,h-inset);border.lineTo(inset+bl,h-inset);border.quadTo(inset,h-inset,inset,h-inset-bl);border.lineTo(inset,inset+tl);border.quadTo(inset,inset,inset+tl,inset);border.close();
    }
    @Override protected void onDraw(Canvas canvas){super.onDraw(canvas);long now=SystemClock.uptimeMillis();if(edge){float stroke=dp(width);borderPath(stroke/2);SweepGradient gradient=new SweepGradient(getWidth()/2f,getHeight()/2f,new int[]{0xff7c6fff,0xffff5eaa,0xfff5ab73,0xff4cddce,0xff539bff,0xff7c6fff},null);rotate.setRotate((now%6500)*360f/6500,getWidth()/2f,getHeight()/2f);gradient.setLocalMatrix(rotate);paint.setShader(gradient);paint.setStyle(Paint.Style.STROKE);paint.setStrokeWidth(stroke+dp(5));paint.setAlpha((int)(80*opacity));canvas.drawPath(border,paint);paint.setStrokeWidth(stroke);paint.setAlpha((int)(220*opacity));canvas.drawPath(border,paint);paint.setStrokeWidth(Math.max(dp(1.5f),stroke*.24f));paint.setAlpha((int)(255*opacity));canvas.drawPath(border,paint);paint.setShader(null);}
        long age=now-gestureAt;if(gestureAt!=0&&age>=0&&age<1000){float alpha=1-age/1000f;paint.setStyle(Paint.Style.STROKE);paint.setStrokeCap(Paint.Cap.ROUND);paint.setStrokeJoin(Paint.Join.ROUND);paint.setColor(0xffb5d3ff);paint.setAlpha((int)(220*alpha));paint.setStrokeWidth(dp(7));float sx=x*getWidth(),sy=y*getHeight(),ex=x2*getWidth(),ey=y2*getHeight();if(swipe){trail.reset();trail.moveTo(sx,sy);trail.lineTo(ex,ey);canvas.drawPath(trail,paint);canvas.drawCircle(sx,sy,dp(9),paint);canvas.drawCircle(ex,ey,dp(12),paint);}else canvas.drawCircle(sx,sy,dp(10)+dp(13)*(1-alpha),paint);}
        if(isShown()&&(edge||(gestureAt!=0&&age<1000)))postInvalidateOnAnimation();else if(!edge)setVisibility(View.GONE);
    }
}
