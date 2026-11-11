#import <UIKit/UIKit.h>
@interface PCScreenEdgeMask : NSObject
@property(nonatomic,readonly) CGSize pixelSize;
- (instancetype)initWithSystemImage:(UIImage *)image screenSize:(CGSize)size topCutout:(CGRect)cutout ignoreTopCutout:(BOOL)ignore cornerRadius:(CGFloat)corner;
- (CGImageRef)copyBandWithWidth:(CGFloat)width CF_RETURNS_RETAINED;
@end
