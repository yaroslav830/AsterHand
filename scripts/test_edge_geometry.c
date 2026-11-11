#include "PCEdgeGeometry.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    PCEdgeProfile se=PCEdgeMakeProfile(375,667,20,0,0,-1);
    PCEdgeProfile notch=PCEdgeMakeProfile(390,844,47,34,47.33,2);
    PCEdgeProfile wide=PCEdgeMakeProfile(375,812,44,34,44,1);
    PCEdgeProfile pill=PCEdgeMakeProfile(393,852,59,34,55,-1);
    assert(se.kind==0 && se.notchWidth==0 && se.corner==0);
    assert(notch.kind==2 && notch.notchWidth>148 && notch.notchWidth<183 && notch.notchDepth==32);
    assert(wide.kind==2 && wide.notchWidth>notch.notchWidth && wide.notchDepth==29);
    assert(pill.kind==1 && pill.notchWidth==0 && pill.corner==55);
    unsigned checked=0;
    for(int width=320;width<=1024;width+=16)for(int top=0;top<=80;top+=4)for(int family=-1;family<=2;family++){
        PCEdgeProfile p=PCEdgeMakeProfile(width,1366,top,34,60,family);
        assert(isfinite(p.corner)&&p.corner>=0&&p.corner<=width/4);
        assert(p.notchWidth>=0&&p.notchWidth<width&&p.notchDepth<=36);
        if(family<0||top>=54)assert(p.notchWidth==0);
        checked++;
    }
    printf("edge geometry: %u profiles passed\n",checked);return 0;
}
