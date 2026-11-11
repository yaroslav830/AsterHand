#include "../Overlay/PCOverlayLayout.h"
#include <assert.h>
#include <stdio.h>
static int equal(double a,double b) {return fabs(a-b)<0.00001;}
int main(void) {
    const double devices[][3]={{320,568,24},{375,667,24},{390,844,60},{393,852,60},{430,932,60},{568,320,16},{667,375,16},{844,390,16},{852,393,16}};
    const double contents[]={260,344,436,272,308,392,484,320,356,440,532,368,202,270,350};unsigned checks=0;
    for(unsigned d=0;d<sizeof(devices)/sizeof(devices[0]);d++)for(unsigned k=0;k<2;k++)for(unsigned c=0;c<sizeof(contents)/sizeof(contents[0]);c++){
        double w=devices[d][0],h=devices[d][1],top=devices[d][2],keyboard=k?(d<2?260:d<5?336:156):0,bottom=h-keyboard-12;
        for(int initial=-1;initial<=1;initial++)for(int step=0;step<=100;step++){
            PCOverlayRect bubble={12+(w-76)*step/100,top+(bottom-top-52)*step/100,52,52};
            PCOverlayMenuLayout result=PCOverlayLayoutMenu(w,h,keyboard,top,bubble,contents[c],initial);
            assert(equal(result.bubble.x,bubble.x)&&equal(result.bubble.y,bubble.y));
            assert(result.panel.x>=16-0.00001&&result.panel.x+result.panel.width<=w-16+0.00001);
            assert(result.panel.y>=top-0.00001&&result.panel.y+result.panel.height<=bottom+0.00001);
            assert(result.panel.height>=0&&result.panel.height<=contents[c]);
            assert(equal(result.side==1?result.bubble.y-result.panel.y-result.panel.height:result.panel.y-result.bubble.y-result.bubble.height,12));
            PCOverlayMenuLayout again=PCOverlayLayoutMenu(w,h,keyboard,top,result.bubble,contents[c],result.side);
            assert(again.side==result.side&&equal(again.panel.y,result.panel.y));checks++;
        }
    }
    /* Translation follows actual coordinates, not an old virtual anchor. */
    PCOverlayRect b={160,400,52,52};PCOverlayMenuLayout a=PCOverlayLayoutMenu(393,852,0,60,b,260,1);
    b.x+=10;b.y+=20;PCOverlayMenuLayout z=PCOverlayLayoutMenu(393,852,0,60,b,260,a.side);
    assert(equal(z.panel.x-a.panel.x,10)&&equal(z.panel.y-a.panel.y,20));
    /* A small keyboard viewport uses a scrollable panel and keeps the 12-point gap. */
    z=PCOverlayLayoutMenu(375,667,304,24,(PCOverlayRect){300,150,52,52},436,0);
    assert(z.panel.height<436&&z.panel.height>0);
    z=PCOverlayLayoutMenuSized(742,393,0,16,(PCOverlayRect){600,300,52,52},202,0,560);
    assert(equal(z.panel.width,560)&&z.panel.y>=16&&z.panel.y+z.panel.height<=381);
    puts("overlay layout: fixed gap, bounds, no bubble snapping, stable direction and translation passed");printf("geometry cases: %u\n",checks);return 0;
}
