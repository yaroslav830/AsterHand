#import "PCKeyboardCompat.h"
#import <objc/runtime.h>

@interface PCLegacyKeyboardGuide : NSObject
@property(nonatomic,weak) UIView *view;
@property(nonatomic,strong) UILayoutGuide *guide;
@property(nonatomic,strong) NSLayoutConstraint *height;
@property(nonatomic,strong) id observer;
@end
@implementation PCLegacyKeyboardGuide
- (void)dealloc {if(self.observer)[NSNotificationCenter.defaultCenter removeObserver:self.observer];}
- (void)changed:(NSNotification *)note {
    UIView *view=self.view;if(!view.window)return;
    CGRect rect=[view convertRect:[note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue] fromView:nil];
    CGRect overlap=CGRectIntersection(view.bounds,rect);
    CGFloat height=!CGRectIsNull(overlap)&&CGRectGetWidth(overlap)>CGRectGetWidth(view.bounds)*.6?MAX(0,CGRectGetMaxY(view.bounds)-CGRectGetMinY(overlap)-view.safeAreaInsets.bottom):0;
    self.height.constant=height;
    double duration=[note.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationOptions options=([note.userInfo[UIKeyboardAnimationCurveUserInfoKey] unsignedIntegerValue]<<16)|UIViewAnimationOptionBeginFromCurrentState;
    [UIView animateWithDuration:duration delay:0 options:options animations:^{[view layoutIfNeeded];} completion:nil];
}
@end

NSLayoutYAxisAnchor *PCKeyboardTopAnchor(UIView *view) {
    if(@available(iOS 15.0,*))return view.keyboardLayoutGuide.topAnchor;
    static char key;PCLegacyKeyboardGuide *owner=objc_getAssociatedObject(view,&key);
    if(!owner){
        owner=[PCLegacyKeyboardGuide new];owner.view=view;owner.guide=[UILayoutGuide new];[view addLayoutGuide:owner.guide];
        owner.height=[owner.guide.heightAnchor constraintEqualToConstant:0];
        [NSLayoutConstraint activateConstraints:@[owner.height,[owner.guide.bottomAnchor constraintEqualToAnchor:view.safeAreaLayoutGuide.bottomAnchor],[owner.guide.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],[owner.guide.trailingAnchor constraintEqualToAnchor:view.trailingAnchor]]];
        __weak PCLegacyKeyboardGuide *weakOwner=owner;
        owner.observer=[NSNotificationCenter.defaultCenter addObserverForName:UIKeyboardWillChangeFrameNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){[weakOwner changed:note];}];
        objc_setAssociatedObject(view,&key,owner,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return owner.guide.topAnchor;
}
