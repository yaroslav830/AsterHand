#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

static inline id PCGeometryObject(id object,NSString *name) {
    SEL selector=NSSelectorFromString(name);Method method=object?class_getInstanceMethod([object class],selector):NULL;
    if(!method||method_getNumberOfArguments(method)!=2)return nil;char *type=method_copyReturnType(method);BOOL valid=type&&type[0]=='@';free(type);
    if(!valid)return nil;@try{return ((id(*)(id,SEL))objc_msgSend)(object,selector);}@catch(NSException *ignored){return nil;}
}
static inline NSDictionary *PCSystemScreenMetrics(UIWindow *window,id *boundaryOut) {
    UIScreen *screen=window.screen?:UIScreen.mainScreen;NSMutableDictionary *result=[NSMutableDictionary new];
    id exclusion=PCGeometryObject(screen,@"_exclusionArea");
    @try{id value=[exclusion valueForKey:@"rect"];if([value isKindOfClass:NSValue.class]&&strcmp([value objCType],@encode(CGRect))==0){CGRect rect=[value CGRectValue];if(!CGRectIsNull(rect)&&!CGRectIsInfinite(rect)&&rect.size.width>=0&&rect.size.width<=screen.bounds.size.width&&rect.size.height<screen.bounds.size.height/2){result[@"exclusion_rect"]=NSStringFromCGRect(rect);result[@"exclusion"]=value;}}}@catch(NSException *ignored){}
    id utilities=PCGeometryObject(screen,@"_boundingPathUtilities");SEL selector=NSSelectorFromString(@"boundingPathForWindow:");Method method=utilities?class_getInstanceMethod([utilities class],selector):NULL;
    id boundary=nil;if(method&&method_getNumberOfArguments(method)==3){char *type=method_copyReturnType(method);BOOL valid=type&&type[0]=='@';free(type);if(valid)@try{boundary=((id(*)(id,SEL,id))objc_msgSend)(utilities,selector,window);}@catch(NSException *ignored){}}
    if(boundaryOut)*boundaryOut=boundary;
    result[@"boundary_class"]=boundary?NSStringFromClass([boundary class]):@"none";
    NSMutableArray *methods=[NSMutableArray new];for(Class type=[boundary class];type&&type!=NSObject.class;type=class_getSuperclass(type)){unsigned int count=0;Method *list=class_copyMethodList(type,&count);for(unsigned int i=0;i<count&&methods.count<80;i++)[methods addObject:@{@"name":NSStringFromSelector(method_getName(list[i])),@"encoding":@(method_getTypeEncoding(list[i]))}];free(list);}result[@"boundary_methods"]=methods;
    return result;
}
