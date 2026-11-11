#import "PCTheme.h"
#import "PCUserGuide.h"
#import "PCLocalization.h"
#import "PCButtonCompat.h"

static NSString *const PCGuideCompletionKey = @"userGuideCompleted.v1";

BOOL PCUserGuideCompleted(void) {
    return [NSUserDefaults.standardUserDefaults boolForKey:PCGuideCompletionKey];
}

static NSDictionary *PCGuideContent(void) {
    static NSDictionary *content;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSData *data = [NSData dataWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"user-guide" ofType:@"json"]];
        content = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : @{};
    });
    return content;
}

@interface PCGuideImageController : UIViewController <UIScrollViewDelegate>
@property(nonatomic, strong) UIImage *image;
@end
@implementation PCGuideImageController {
    UIScrollView *_scroll;
    UIImageView *_imageView;
    CGSize _viewport;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=PCLocalized(@"英文界面示例");
    self.view.backgroundColor=PCCanvasColor();
    _scroll=[UIScrollView new];_scroll.delegate=self;_scroll.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:_scroll];
    _imageView=[[UIImageView alloc] initWithImage:self.image];[_scroll addSubview:_imageView];_scroll.contentSize=self.image.size;
    UILayoutGuide *safe=self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[[_scroll.topAnchor constraintEqualToAnchor:safe.topAnchor],[_scroll.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],[_scroll.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],[_scroll.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor]]];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGSize size=_scroll.bounds.size;
    if(!CGSizeEqualToSize(size,_viewport)&&size.width>0&&size.height>0){
        _viewport=size;
        CGFloat fit=MIN(size.width/MAX(1,self.image.size.width),size.height/MAX(1,self.image.size.height));
        _scroll.minimumZoomScale=fit;_scroll.maximumZoomScale=MAX(1,fit*4);_scroll.zoomScale=fit;
        [self centerImage];
    }
}
- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {return _imageView;}
- (void)scrollViewDidZoom:(UIScrollView *)scrollView {[self centerImage];}
- (void)centerImage {
    CGFloat horizontal=MAX(0,(_scroll.bounds.size.width-_imageView.frame.size.width)/2);
    CGFloat vertical=MAX(0,(_scroll.bounds.size.height-_imageView.frame.size.height)/2);
    _scroll.contentInset=UIEdgeInsetsMake(vertical,horizontal,vertical,horizontal);
}
@end

@implementation PCUserGuideController {
    NSUInteger _step;
    UIScrollView *_scroll;
    UIStackView *_content;
    UIStackView *_controls;
    BOOL _finishing;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = PCCanvasColor();
    self.view.tintColor = PCTextColor();
    self.navigationController.navigationBar.tintColor = PCTextColor();
    [self rebuild];
}

- (UILabel *)label:(NSString *)text style:(UIFontTextStyle)style secondary:(BOOL)secondary {
    UILabel *label = [UILabel new];
    label.text = PCLocalized(text);
    label.numberOfLines = 0;
    label.font = [UIFont preferredFontForTextStyle:style];
    label.adjustsFontForContentSizeCategory = YES;
    label.textColor = secondary ? PCMutedColor() : PCTextColor();
    if ([style isEqual:UIFontTextStyleTitle1] || [style isEqual:UIFontTextStyleTitle2]) label.accessibilityTraits |= UIAccessibilityTraitHeader;
    return label;
}

- (UIButton *)button:(NSString *)title selector:(SEL)selector primary:(BOOL)primary {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    PCStyleButton(button, primary ? PCButtonFilled : PCButtonTinted);
    if (@available(iOS 15.0, *)) {
        UIButtonConfiguration *configuration=button.configuration;
        configuration.title=PCLocalized(title);
        configuration.baseBackgroundColor=primary ? PCTextColor() : UIColor.tertiarySystemFillColor;
        configuration.baseForegroundColor=primary ? PCCanvasColor() : PCTextColor();
        button.configuration=configuration;
    }
    [button setTitle:PCLocalized(title) forState:UIControlStateNormal];
    button.titleLabel.numberOfLines = 0;
    button.titleLabel.textAlignment = NSTextAlignmentCenter;
    button.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    button.titleLabel.adjustsFontForContentSizeCategory = YES;
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:50].active = YES;
    [button addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)addImage:(NSDictionary *)entry {
    NSString *name = entry[@"iosImage"];
    UIImage *image = name.length ? [UIImage imageWithContentsOfFile:[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:name]] : nil;
    if (!image) return;
    UIImageView *view = [[UIImageView alloc] initWithImage:image];
    view.contentMode = UIViewContentModeScaleAspectFit;
    view.clipsToBounds = YES;
    view.layer.cornerRadius = 14;
    view.isAccessibilityElement = YES;
    view.accessibilityLabel = PCLocalized(@"英文界面示例");
    view.accessibilityTraits |= UIAccessibilityTraitButton;
    view.userInteractionEnabled = YES;
    [view addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(enlargeImage:)]];
    CGFloat ratio = image.size.height / MAX(1, image.size.width);
    NSLayoutConstraint *height = [view.heightAnchor constraintEqualToAnchor:view.widthAnchor multiplier:ratio];
    height.priority = UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[height, [view.heightAnchor constraintLessThanOrEqualToConstant:480]]];
    [_content addArrangedSubview:view];
    [_content addArrangedSubview:[self label:@"英文界面示例" style:UIFontTextStyleCaption1 secondary:YES]];
}

- (void)enlargeImage:(UITapGestureRecognizer *)gesture {
    PCGuideImageController *preview=[PCGuideImageController new];
    preview.image=((UIImageView *)gesture.view).image;
    [self.navigationController pushViewController:preview animated:YES];
}

- (void)rebuild {
    [_scroll removeFromSuperview];
    [_controls removeFromSuperview];
    _controls=nil;
    self.title = self.onboarding ? PCLocalized(@"快速入门") : self.topic ? PCLocalized(self.topic[@"title"]) : PCLocalized(@"使用指南");
    self.navigationItem.hidesBackButton = self.onboarding;
    self.navigationItem.leftBarButtonItem = self.onboarding ? [[UIBarButtonItem alloc] initWithTitle:PCLocalized(@"暂时跳过") style:UIBarButtonItemStylePlain target:self action:@selector(skip)] : nil;
    _scroll = [UIScrollView new];
    _scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_scroll];
    _content = [UIStackView new];
    _content.axis = UILayoutConstraintAxisVertical;
    _content.spacing = 18;
    _content.translatesAutoresizingMaskIntoConstraints = NO;
    [_scroll addSubview:_content];
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    if(self.onboarding){
        _controls=[UIStackView new];_controls.axis=UILayoutConstraintAxisVertical;_controls.spacing=10;_controls.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:_controls];
        [NSLayoutConstraint activateConstraints:@[[_controls.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-12],[_controls.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:20],[_controls.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-20]]];
    }
    [NSLayoutConstraint activateConstraints:@[
        [_scroll.topAnchor constraintEqualToAnchor:safe.topAnchor], [_scroll.bottomAnchor constraintEqualToAnchor:_controls ? _controls.topAnchor : safe.bottomAnchor constant:_controls ? -12 : 0],
        [_scroll.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor], [_scroll.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [_content.topAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.topAnchor constant:24],
        [_content.bottomAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.bottomAnchor constant:-24],
        [_content.centerXAnchor constraintEqualToAnchor:_scroll.frameLayoutGuide.centerXAnchor],
        [_content.widthAnchor constraintEqualToAnchor:_scroll.frameLayoutGuide.widthAnchor constant:-40]
    ]];
    if (self.onboarding) [self buildStep];
    else if (self.topic) [self buildTopic];
    else [self buildIndex];
}

- (void)buildStep {
    NSArray *steps = PCGuideContent()[@"steps"];
    if (!steps.count) { [_controls addArrangedSubview:[self button:@"开始使用" selector:@selector(skip) primary:YES]]; return; }
    NSDictionary *entry = steps[MIN(_step, steps.count - 1)];
    UILabel *progress = [self label:[NSString stringWithFormat:@"%lu / %lu", (unsigned long)_step + 1, (unsigned long)steps.count] style:UIFontTextStyleCaption1 secondary:YES];
    progress.accessibilityLabel = [NSString stringWithFormat:@"%@ %lu / %lu", PCLocalized(@"快速入门"), (unsigned long)_step + 1, (unsigned long)steps.count];
    [_content addArrangedSubview:progress];
    UIProgressView *bar = [UIProgressView new];
    bar.progress = (float)(_step + 1) / steps.count;
    bar.progressTintColor = UIColor.systemGreenColor;
    [_content addArrangedSubview:bar];
    UIImageView *symbol = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:entry[@"symbol"]]];
    symbol.contentMode = UIViewContentModeScaleAspectFit;
    symbol.tintColor = UIColor.systemGreenColor;
    [symbol.heightAnchor constraintEqualToConstant:62].active = YES;
    [_content addArrangedSubview:symbol];
    [_content addArrangedSubview:[self label:entry[@"title"] style:UIFontTextStyleTitle1 secondary:NO]];
    [_content addArrangedSubview:[self label:entry[@"iosText"] ?: entry[@"text"] style:UIFontTextStyleBody secondary:NO]];
    [self addImage:entry];
    [_content addArrangedSubview:[self label:entry[@"tip"] style:UIFontTextStyleSubheadline secondary:YES]];
    BOOL last = _step + 1 == steps.count;
    if (last) [_controls addArrangedSubview:[self button:@"去连接 AI" selector:@selector(connect) primary:YES]];
    UIStackView *navigation=[UIStackView new];navigation.axis=UILayoutConstraintAxisHorizontal;navigation.spacing=10;navigation.distribution=UIStackViewDistributionFillEqually;
    if (_step) [navigation addArrangedSubview:[self button:@"上一步" selector:@selector(previous) primary:NO]];
    [navigation addArrangedSubview:[self button:last ? @"开始使用" : @"下一步" selector:@selector(next) primary:!last]];
    [_controls addArrangedSubview:navigation];
}

- (void)buildIndex {
    [_content addArrangedSubview:[self label:@"了解功能，从这里开始" style:UIFontTextStyleTitle1 secondary:NO]];
    [_content addArrangedSubview:[self label:PCGuideContent()[@"steps"][0][@"text"] style:UIFontTextStyleBody secondary:YES]];
    [_content addArrangedSubview:[self button:@"重新查看入门引导" selector:@selector(replay) primary:YES]];
    NSArray *topics = PCGuideContent()[@"topics"];
    for (NSUInteger i = 0; i < topics.count; i++) {
        UIButton *button = [self button:topics[i][@"title"] selector:@selector(openTopic:) primary:NO];
        button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
        button.titleLabel.textAlignment = NSTextAlignmentLeft;
        button.tag = i;
        [_content addArrangedSubview:button];
    }
}

- (void)buildTopic {
    [_content addArrangedSubview:[self label:self.topic[@"title"] style:UIFontTextStyleTitle1 secondary:NO]];
    [self addImage:self.topic];
    NSArray *paragraphs = [self.topic[@"paragraphs"] arrayByAddingObjectsFromArray:self.topic[@"iosParagraphs"] ?: @[]];
    for (NSString *text in paragraphs) [_content addArrangedSubview:[self label:text style:UIFontTextStyleBody secondary:NO]];
}

- (void)openTopic:(UIButton *)button {
    PCUserGuideController *page = [PCUserGuideController new];
    page.topic = PCGuideContent()[@"topics"][button.tag];
    [self.navigationController pushViewController:page animated:YES];
}

- (void)replay {
    PCUserGuideController *page = [PCUserGuideController new];
    page.onboarding = YES;
    __weak typeof(self) owner = self;
    page.finished = ^(BOOL connectAI) {
        PCUserGuideController *guide = owner;
        [guide.navigationController popToViewController:guide animated:!connectAI];
        if (connectAI && guide.finished) guide.finished(YES);
    };
    [self.navigationController pushViewController:page animated:YES];
}

- (void)finish:(BOOL)connectAI {
    if (_finishing) return;
    _finishing = YES;
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:PCGuideCompletionKey];
    if (self.finished) self.finished(connectAI);
}
- (void)skip { [self finish:NO]; }
- (void)connect { [self finish:YES]; }
- (void)next {
    if (_step + 1 >= [PCGuideContent()[@"steps"] count]) { [self finish:NO]; return; }
    _step++;
    [self rebuild];
    UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, nil);
}
- (void)previous {
    if (_step) _step--;
    [self rebuild];
    UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, nil);
}
@end
