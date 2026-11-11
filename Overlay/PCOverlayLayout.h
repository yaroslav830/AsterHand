#ifndef PC_OVERLAY_LAYOUT_H
#define PC_OVERLAY_LAYOUT_H
#include <math.h>

typedef struct { double x,y,width,height; } PCOverlayRect;
typedef struct { PCOverlayRect bubble,panel; int side; } PCOverlayMenuLayout;
static inline double PCOverlayClamp(double x,double low,double high) { return fmin(fmax(x,low),fmax(low,high)); }

/* side: 1 above, -1 below, 0 choose on opening. The bubble never snaps to a menu corner. */
static inline PCOverlayMenuLayout PCOverlayLayoutMenuSized(double screenWidth,double screenHeight,double keyboardHeight,double top,PCOverlayRect bubble,double contentHeight,int side,double preferredWidth) {
    const double gap=12,margin=16,bottom=screenHeight-fmax(0,keyboardHeight)-12;
    bubble.x=PCOverlayClamp(bubble.x,12,screenWidth-bubble.width-12);
    bubble.y=PCOverlayClamp(bubble.y,top,bottom-bubble.height);
    double above=fmax(0,bubble.y-gap-top),below=fmax(0,bottom-bubble.y-bubble.height-gap);
    if(side!=1&&side!=-1) {
        if(above>=contentHeight)side=1;
        else if(below>=contentHeight)side=-1;
        else side=above>=below?1:-1;
    }else{
        double current=side==1?above:below,other=side==1?below:above;
        /* Hysteresis keeps an ordinary drag from flipping the menu back and forth. */
        if((other>=contentHeight&&current<contentHeight-24)||(current<fmin(160,contentHeight)&&other>current+48)||current<=0)side=-side;
    }
    double height=fmin(contentHeight,side==1?above:below),width=fmin(preferredWidth,screenWidth-2*margin);
    PCOverlayRect panel={PCOverlayClamp(bubble.x+bubble.width/2-width/2,margin,screenWidth-margin-width),side==1?bubble.y-gap-height:bubble.y+bubble.height+gap,width,height};
    return (PCOverlayMenuLayout){bubble,panel,side};
}
static inline PCOverlayMenuLayout PCOverlayLayoutMenu(double screenWidth,double screenHeight,double keyboardHeight,double top,PCOverlayRect bubble,double contentHeight,int side) {return PCOverlayLayoutMenuSized(screenWidth,screenHeight,keyboardHeight,top,bubble,contentHeight,side,332);}
#endif
