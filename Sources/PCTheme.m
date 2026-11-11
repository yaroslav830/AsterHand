#import "PCTheme.h"
#import "PCPairing.h"
static void PCConfigureAppearance(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        UINavigationBarAppearance *bar=[UINavigationBarAppearance new];
        [bar configureWithOpaqueBackground];bar.backgroundColor=PCCanvasColor();bar.shadowColor=PCBorderColor();
        bar.titleTextAttributes=@{NSForegroundColorAttributeName:PCTextColor(),NSFontAttributeName:[UIFont systemFontOfSize:16 weight:UIFontWeightSemibold]};
        UINavigationBar.appearance.standardAppearance=bar;UINavigationBar.appearance.scrollEdgeAppearance=bar;
        UINavigationBar.appearance.compactAppearance=bar;UINavigationBar.appearance.tintColor=PCTextColor();
        UITableView.appearance.backgroundColor=PCCanvasColor();UITableView.appearance.separatorColor=PCBorderColor();
        UITableViewCell.appearance.backgroundColor=PCSurfaceColor();
        UISwitch.appearance.onTintColor=PCSuccessColor();UISlider.appearance.minimumTrackTintColor=PCSuccessColor();
    });
}
@implementation PCBrandImageView
- (instancetype)init {return [self initWithFrame:CGRectZero];}
- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])){self.contentMode=UIViewContentModeScaleAspectFit;self.backgroundColor=UIColor.clearColor;self.accessibilityLabel=@"AsterHand";[self updateBrandImage];}return self;
}
- (instancetype)initWithCoder:(NSCoder *)coder {if((self=[super initWithCoder:coder])){self.contentMode=UIViewContentModeScaleAspectFit;self.backgroundColor=UIColor.clearColor;[self updateBrandImage];}return self;}
- (void)updateBrandImage {
    BOOL dark=self.traitCollection.userInterfaceStyle==UIUserInterfaceStyleDark;
    UIImage *image=[UIImage imageNamed:dark?@"AsterHandBrandDark":@"AsterHandBrand"];
    if(!image)image=[UIImage imageNamed:dark?@"AgentGoIconDark1024":@"AgentGoIcon1024"];
    self.image=[image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}
- (void)didMoveToWindow {[super didMoveToWindow];[self updateBrandImage];}
- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    if(previous.userInterfaceStyle!=self.traitCollection.userInterfaceStyle)[self updateBrandImage];
}
@end
@implementation PCSurfaceView
- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])){self.backgroundColor=PCSurfaceColor();self.layer.cornerRadius=PCCardRadius;self.layer.borderWidth=1.0/UIScreen.mainScreen.scale;[self updateBorder];}return self;
}
- (void)updateBorder {self.layer.borderColor=[PCBorderColor() resolvedColorWithTraitCollection:self.traitCollection].CGColor;}
- (void)traitCollectionDidChange:(UITraitCollection *)previous {[super traitCollectionDidChange:previous];[self updateBorder];}
@end
void PCSyncApplicationIcon(UIWindow *window) {
    UIApplication *app=UIApplication.sharedApplication;
    if(app.applicationState!=UIApplicationStateActive||!app.supportsAlternateIcons)return;
    // A cold-start connection request must show its consent card first. iOS
    // presents a system confirmation when an alternate launcher icon changes.
    if(PCPairPending().count)return;
    NSString *name=window.traitCollection.userInterfaceStyle==UIUserInterfaceStyleDark?@"AsterHandDark":nil;
    if([app.alternateIconName isEqual:name]||(!app.alternateIconName&&!name))return;
    static BOOL changing;static NSString *failedStyle;if(changing||[failedStyle isEqual:name?:@"light"])return;changing=YES;
    [app setAlternateIconName:name completionHandler:^(NSError *error){dispatch_async(dispatch_get_main_queue(),^{changing=NO;failedStyle=error?(name?:@"light"):nil;if(error)NSLog(@"AsterHand icon appearance: %@",error.localizedDescription);else PCSyncApplicationIcon(window);});}];
}
@implementation PCThemeWindow
- (instancetype)initWithFrame:(CGRect)frame {PCConfigureAppearance();if((self=[super initWithFrame:frame])){self.backgroundColor=PCCanvasColor();self.tintColor=PCTextColor();}return self;}
- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    if(previous.userInterfaceStyle!=self.traitCollection.userInterfaceStyle)dispatch_async(dispatch_get_main_queue(),^{PCSyncApplicationIcon(self);});
}
@end
