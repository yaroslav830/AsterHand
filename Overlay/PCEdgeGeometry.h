#pragma once
#include <math.h>
typedef struct {double corner,notchWidth,notchDepth,notchCorner,shoulder;int kind;} PCEdgeProfile;
// family: -1 flat/pill/no cutout, 1 wide notch, 2 compact notch, 0 infer.
static inline PCEdgeProfile PCEdgeMakeProfile(double width,double height,double safeTop,double safeBottom,double radius,int family){
    double shortSide=fmin(width,height);PCEdgeProfile p={0};p.corner=fmax(0,fmin(radius,shortSide/4));p.kind=p.corner>0?1:0;
    if(family<0||safeTop>=54)return p;
    if(!family&&safeTop>=35&&safeTop<54&&safeBottom>=15)family=safeTop>=46?2:1;
    if(family){p.kind=2;p.shoulder=6;p.notchWidth=fmin(shortSide-2*(p.corner+14),family==2?fmin(183,fmax(148,shortSide*.43)):fmin(225,fmax(180,shortSide*.55)));p.notchWidth=fmax(0,p.notchWidth);p.notchDepth=fmin(36,fmax(28,safeTop>0?safeTop-15:32));p.notchCorner=fmin(14,p.notchDepth/2);}
    return p;
}
