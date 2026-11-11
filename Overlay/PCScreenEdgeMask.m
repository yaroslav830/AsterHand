#import "PCScreenEdgeMask.h"
#include "PCEdgeDistance.h"
#include <stdlib.h>
#include <stdint.h>

static void ReleasePixels(void *context,const void *bytes,size_t size){free((void *)bytes);}
@implementation PCScreenEdgeMask {int _width,_height,_stride;float *_distance;uint8_t *_coverage;double _scale;BOOL _roundInnerCorners;}
- (CGSize)pixelSize{return CGSizeMake(_width,_height);}
- (instancetype)initWithSystemImage:(UIImage *)image screenSize:(CGSize)size topCutout:(CGRect)cutout ignoreTopCutout:(BOOL)ignore cornerRadius:(CGFloat)corner {
    if(!(self=[super init]))return nil;CGImageRef source=image.CGImage;if(!source||size.width<=0||size.height<=0)return nil;
    size_t width=CGImageGetWidth(source),height=CGImageGetHeight(source);if(width<16||height<16||width>4096||height>4096||width*height>12*1024*1024)return nil;
    double sx=width/size.width,sy=height/size.height;if(sx<.5||sx>5||fabs(sx-sy)>.05)return nil;_scale=sx;_width=(int)width;_height=(int)height;_stride=_width+2;
    _roundInnerCorners=corner<.1&&cutout.size.height<1;
    size_t count=(width+2)*(height+2);_distance=malloc(count*sizeof(float));_coverage=calloc(count,1);uint8_t *rgba=calloc(width*height,4);uint32_t *queue=malloc(count*sizeof(uint32_t));
    if(!_distance||!_coverage||!rgba||!queue){free(rgba);free(queue);return nil;}
    CGColorSpaceRef color=CGColorSpaceCreateDeviceRGB();CGContextRef context=CGBitmapContextCreate(rgba,width,height,8,width*4,color,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);CGColorSpaceRelease(color);
    if(!context){free(rgba);free(queue);return nil;}CGContextDrawImage(context,CGRectMake(0,0,width,height),source);CGContextRelease(context);
    unsigned minimumAlpha=255;for(size_t p=0;p<width*height;p++)minimumAlpha=MIN(minimumAlpha,rgba[p*4+3]);size_t center=((height/2)*width+width/2)*4;BOOL alphaMask=minimumAlpha<250&&rgba[center+3]>128;BOOL invert=rgba[center]<128;
    for(size_t p=0;p<count;p++)_distance[p]=1e12f;
    int topLimit=(int)ceil(MAX(0,CGRectGetMaxY(cutout)+1)*_scale),cornerLimit=(int)ceil(MAX(corner,1)*_scale);
    for(int y=0;y<_height;y++)for(int x=0;x<_width;x++){size_t sourceIndex=((size_t)y*_width+x)*4;unsigned value=alphaMask?rgba[sourceIndex+3]:(rgba[sourceIndex]+rgba[sourceIndex+1]+rgba[sourceIndex+2])/3;if(!alphaMask&&invert)value=255-value;if(ignore&&y<topLimit&&x>=cornerLimit&&x<_width-cornerLimit)value=255;_coverage[(size_t)(y+1)*_stride+x+1]=(uint8_t)value;}free(rgba);
    // Only outside pixels connected to a display edge are boundary seeds.
    // Interior holes (for example a Dynamic Island) do not create extra rings.
    size_t head=0,tail=1;queue[0]=0;_distance[0]=0;
    while(head<tail){size_t index=queue[head++];int x=(int)(index%_stride),y=(int)(index/_stride);size_t adjacent[4];unsigned n=0;if(x>0)adjacent[n++]=index-1;if(x<_stride-1)adjacent[n++]=index+1;if(y>0)adjacent[n++]=index-_stride;if(y<_height+1)adjacent[n++]=index+_stride;for(unsigned i=0;i<n;i++){size_t next=adjacent[i];if(_coverage[next]<128&&_distance[next]!=0){_distance[next]=0;queue[tail++]=(uint32_t)next;}}}free(queue);
    for(size_t p=0;p<count;p++)if(_distance[p]!=0&&_coverage[p]<128)_coverage[p]=255;
    int maximum=MAX(_stride,_height+2);float *input=malloc(maximum*sizeof(float)),*output=malloc(maximum*sizeof(float));int *sites=malloc(maximum*sizeof(int));double *limits=malloc((maximum+1)*sizeof(double));
    if(!input||!output||!sites||!limits){free(input);free(output);free(sites);free(limits);return nil;}PCEdgeDistanceTransform(_distance,_stride,_height+2,input,output,sites,limits);free(input);free(output);free(sites);free(limits);return self;
}
- (CGImageRef)copyBandWithWidth:(CGFloat)width {
    if(!isfinite(width)||width<=0||!_distance)return NULL;size_t count=(size_t)_width*_height;uint8_t *pixels=malloc(count*4);if(!pixels)return NULL;double radius=width*_scale;
    for(int y=0;y<_height;y++)for(int x=0;x<_width;x++){size_t index=(size_t)(y+1)*_stride+x+1,p=((size_t)y*_width+x)*4;double coverage=MAX(0,MIN(1,radius+.5-sqrt(_distance[index])));if(_roundInnerCorners){double dx=MIN(x+.5,_width-x-.5),dy=MIN(y+.5,_height-y-.5);if(dx>=radius&&dx<2*radius&&dy>=radius&&dy<2*radius)coverage=MAX(coverage,MAX(0,MIN(1,hypot(2*radius-dx,2*radius-dy)-radius+.5)));}uint8_t alpha=(uint8_t)MIN(_coverage[index],lround(coverage*255));pixels[p]=pixels[p+1]=pixels[p+2]=pixels[p+3]=alpha;}
    CGDataProviderRef provider=CGDataProviderCreateWithData(NULL,pixels,count*4,ReleasePixels);if(!provider){free(pixels);return NULL;}CGColorSpaceRef color=CGColorSpaceCreateDeviceRGB();CGImageRef image=CGImageCreate(_width,_height,8,32,_width*4,color,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big,provider,NULL,NO,kCGRenderingIntentDefault);CGColorSpaceRelease(color);CGDataProviderRelease(provider);return image;
}
- (void)dealloc {free(_distance);free(_coverage);}
@end
