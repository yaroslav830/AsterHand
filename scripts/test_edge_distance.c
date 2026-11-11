#include "PCEdgeDistance.h"
#include <assert.h>
#include <stdio.h>
#include <stdint.h>
int main(void){float grid[32*32],original[32*32],in[32],out[32];int sites[32];double limits[33];uint32_t random=7;unsigned checked=0;
    for(int test=0;test<100;test++){int width=3+test%27,height=3+(test*7)%27;for(int y=0;y<height;y++)for(int x=0;x<width;x++){random=random*1664525+1013904223;grid[y*width+x]=original[y*width+x]=(x==0||y==0||x==width-1||y==height-1||(random%23==0))?0:1e12f;}
        PCEdgeDistanceTransform(grid,width,height,in,out,sites,limits);
        for(int y=0;y<height;y++)for(int x=0;x<width;x++){double best=1e12;for(int yy=0;yy<height;yy++)for(int xx=0;xx<width;xx++)if(original[yy*width+xx]==0){double d=(x-xx)*(x-xx)+(y-yy)*(y-yy);if(d<best)best=d;}assert(fabs(grid[y*width+x]-best)<.001);checked++;}}
    printf("native boundary distances: %u pixels match brute force\n",checked);return 0;}
