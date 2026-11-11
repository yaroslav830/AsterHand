#pragma once
#include <stddef.h>
#include <math.h>

// Exact squared Euclidean distance transform, not a rectangular erosion.
static inline void PCEdgeDistanceLine(const float *input,float *output,int count,int *sites,double *limits){
    int last=0;sites[0]=0;limits[0]=-INFINITY;limits[1]=INFINITY;
    for(int q=1;q<count;q++){double crossing;for(;;){int p=sites[last];crossing=((double)input[q]+(double)q*q-input[p]-(double)p*p)/(2.0*(q-p));if(crossing>limits[last])break;last--;}last++;sites[last]=q;limits[last]=crossing;limits[last+1]=INFINITY;}
    last=0;for(int q=0;q<count;q++){while(limits[last+1]<q)last++;double delta=q-sites[last];output[q]=(float)(delta*delta+input[sites[last]]);}
}
static inline void PCEdgeDistanceTransform(float *grid,int width,int height,float *input,float *output,int *sites,double *limits){
    for(int y=0;y<height;y++){for(int x=0;x<width;x++)input[x]=grid[(size_t)y*width+x];PCEdgeDistanceLine(input,output,width,sites,limits);for(int x=0;x<width;x++)grid[(size_t)y*width+x]=output[x];}
    for(int x=0;x<width;x++){for(int y=0;y<height;y++)input[y]=grid[(size_t)y*width+x];PCEdgeDistanceLine(input,output,height,sites,limits);for(int y=0;y<height;y++)grid[(size_t)y*width+x]=output[y];}
}
