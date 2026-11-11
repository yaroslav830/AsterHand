#import "PCTheme.h"
#import "PCLocalization.h"
#import "PCButtonCompat.h"
#import "PCChatTimeline.h"

@interface PCChatTimeline () <UITableViewDataSource, UITableViewDelegate>
@property(nonatomic, strong) NSArray<NSDictionary *> *messages;
@property(nonatomic, strong) UIView *welcome;
@property(nonatomic) BOOL adjustingOffset;
@property(nonatomic,copy) NSString *transcript;
@property(nonatomic,strong) NSDictionary *pendingQuestion;
@property(nonatomic) BOOL questionSubmitted;
@property(nonatomic,copy) NSString *questionSendError;
@property(nonatomic) CGFloat questionLayoutWidth;
@end
@implementation PCChatTimeline
- (instancetype)init {
    if ((self = [super initWithFrame:CGRectZero style:UITableViewStylePlain])) {
        self.dataSource = self; self.delegate = self;
        self.backgroundColor = PCCanvasColor();
        self.separatorStyle = UITableViewCellSeparatorStyleNone;
        self.rowHeight = UITableViewAutomaticDimension; self.estimatedRowHeight = 100;
        self.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
        self.alwaysBounceVertical = YES; self.contentInset = UIEdgeInsetsMake(12,0,20,0);
        self.accessibilityLabel = PCLocalized(@"聊天消息");
        self.welcome = [UIView new];
        PCBrandImageView *brand = [PCBrandImageView new];
        [brand.heightAnchor constraintEqualToConstant:44].active = YES;
        UILabel *title = [UILabel new]; title.tag=19001; title.text = PCLocalized(@"今天想做些什么？"); title.font = [UIFont systemFontOfSize:24 weight:UIFontWeightSemibold]; title.textAlignment = NSTextAlignmentCenter;
        UILabel *hint = [UILabel new]; hint.tag=19002; hint.text = PCLocalized(@"聊天、编写代码，或控制你的设备"); hint.font = [UIFont systemFontOfSize:14]; hint.textColor = PCMutedColor(); hint.textAlignment = NSTextAlignmentCenter;
        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[brand,title,hint]];
        stack.axis = UILayoutConstraintAxisVertical; stack.spacing = 14; stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self.welcome addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[[stack.centerXAnchor constraintEqualToAnchor:self.welcome.centerXAnchor], [stack.centerYAnchor constraintEqualToAnchor:self.welcome.centerYAnchor constant:-40], [stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.welcome.leadingAnchor constant:12]]];
        self.messages = @[]; self.backgroundView = self.welcome; self.automaticFollow = YES;
    }
    return self;
}
- (void)refreshUILanguage {((UILabel *)[self.welcome viewWithTag:19001]).text=PCLocalized(@"今天想做些什么？");((UILabel *)[self.welcome viewWithTag:19002]).text=PCLocalized(@"聊天、编写代码，或控制你的设备");[self rebuildMessages];}
- (void)showTranscript:(NSString *)transcript {self.transcript=transcript?:@"";[self rebuildMessages];}
- (void)showPendingQuestion:(NSDictionary *)question {
    if([self.pendingQuestion isEqual:question]||(!self.pendingQuestion&&!question))return;
    BOOL newPrompt=![self.pendingQuestion[@"id"] isEqual:question[@"id"]]||![self.pendingQuestion[@"job_id"] isEqual:question[@"job_id"]];
    self.pendingQuestion=[question copy];if(newPrompt){self.questionSubmitted=NO;self.questionSendError=nil;}
    if([question[@"client_submitted"] boolValue])self.questionSubmitted=YES;
    [self rebuildMessages];if(question&&newPrompt){self.automaticFollow=YES;if(self.followChanged)self.followChanged(YES);[self jumpToLatest];}
}
- (void)rebuildMessages {
    NSString *text = self.transcript ?: @"";
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"(?m)^\\[([^\\]\\r\\n]{1,100})\\]\\r?\\n" options:0 error:nil];
    NSArray<NSTextCheckingResult *> *matches = [regex matchesInString:text options:0 range:NSMakeRange(0,text.length)];
    NSMutableArray *messages = [NSMutableArray new];
    for (NSUInteger i = 0; i < matches.count; i++) {
        NSTextCheckingResult *match = matches[i]; NSUInteger start = NSMaxRange(match.range), end = i+1<matches.count ? matches[i+1].range.location : text.length;
        NSString *kind = [text substringWithRange:[match rangeAtIndex:1]];
        NSString *body = [[text substringWithRange:NSMakeRange(start,end-start)] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!body.length || [@[@"欢迎",@"新对话"] containsObject:kind]) continue;
        BOOL user = [kind isEqual:@"你"];
        BOOL detail = [@[@"进度",@"用量",@"工具请求",@"工具结果",@"自动允许",@"本机诊断",@"离线自检",@"后台",@"已停止",@"附件",@"错误",@"提示",@"附件错误"] containsObject:kind];
        [messages addObject:@{@"kind":kind,@"body":body,@"user":@(user),@"detail":@(detail)}];
    }
    if (!matches.count && text.length) [messages addObject:@{@"kind":@"记录",@"body":text,@"user":@NO,@"detail":@YES}];
    if(self.pendingQuestion){NSDictionary *last=messages.lastObject;if([last[@"kind"] isEqual:@"提问"]&&[last[@"body"] isEqual:self.pendingQuestion[@"text"]])[messages removeLastObject];[messages addObject:@{@"kind":[self.pendingQuestion[@"kind"] isEqual:@"root_permission"]?@"Root 权限申请":@"需要你回答",@"body":self.pendingQuestion[@"text"]?:@"",@"user":@NO,@"detail":@NO,@"question":@YES}];}
    self.messages = messages; self.backgroundView = messages.count ? nil : self.welcome; [self reloadData];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.messages.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *item = self.messages[indexPath.row]; BOOL user = [item[@"user"] boolValue], detail = [item[@"detail"] boolValue];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil]; cell.backgroundColor = UIColor.clearColor; cell.selectionStyle = UITableViewCellSelectionStyleNone;
    BOOL question=[item[@"question"] boolValue];
    UIView *bubble = [UIView new]; bubble.translatesAutoresizingMaskIntoConstraints = NO;
    bubble.backgroundColor = user || detail || question ? PCSoftColor() : UIColor.clearColor; bubble.layer.cornerRadius = user ? PCCardRadius : PCControlRadius;
    UILabel *body = [UILabel new]; body.numberOfLines = 0; body.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody]; body.adjustsFontForContentSizeCategory = YES;
    NSString *full = item[@"body"];if([@[@"进度",@"状态",@"用量",@"提示",@"错误",@"后台",@"已停止",@"自动允许"] containsObject:item[@"kind"]]||(question&&[self.pendingQuestion[@"kind"] isEqual:@"root_permission"]))full=PCLocalized(full); body.text = detail && full.length>180 ? [[full substringToIndex:180] stringByAppendingString:PCLocalized(@"…\n查看详情 ›")] : full;
    body.textColor = detail ? PCMutedColor() : PCTextColor(); if (detail) body.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    UILabel *heading = [UILabel new]; heading.text = PCLocalized(item[@"kind"]); heading.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold]; heading.textColor = [item[@"kind"] containsString:@"错误"] ? PCDangerColor() : PCMutedColor();
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:user ? @[body] : @[heading,body]]; stack.axis = UILayoutConstraintAxisVertical; stack.spacing = 6; stack.translatesAutoresizingMaskIntoConstraints = NO;
    if(question){
        BOOL rootQuestion=[self.pendingQuestion[@"kind"] isEqual:@"root_permission"];
        heading.text=self.questionSubmitted?PCLocalized(@"回答已发送"):rootQuestion?PCLocalized(@"Root 权限申请"):PCLocalized(@"需要你回答");
        NSArray *options=[self.pendingQuestion[@"options"] isKindOfClass:NSArray.class]?self.pendingQuestion[@"options"]:@[];
        NSString *job=self.pendingQuestion[@"job_id"],*prompt=self.pendingQuestion[@"id"];
        UIFont *font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];CGFloat available=MAX(80,(self.bounds.size.width>0?self.bounds.size.width:UIScreen.mainScreen.bounds.size.width-16)-92);
        __weak typeof(self) owner=self;
        for(id option in options){if(![option isKindOfClass:NSString.class]||![option length])continue;NSString *answer=[option copy];NSString *label=rootQuestion?PCLocalized(answer):answer;
            UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];if(@available(iOS 15.0,*)){UIButtonConfiguration *config=UIButtonConfiguration.tintedButtonConfiguration;config.baseForegroundColor=PCTextColor();config.baseBackgroundColor=PCSoftColor();config.title=label;config.titleAlignment=UIButtonConfigurationTitleAlignmentLeading;config.titleLineBreakMode=NSLineBreakByWordWrapping;config.contentInsets=NSDirectionalEdgeInsetsMake(12,16,12,16);button.configuration=config;}else{PCStyleButton(button,PCButtonTinted);button.contentEdgeInsets=UIEdgeInsetsMake(12,16,12,16);[button setTitle:label forState:UIControlStateNormal];button.titleLabel.lineBreakMode=NSLineBreakByWordWrapping;}button.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeft;button.titleLabel.numberOfLines=0;button.titleLabel.font=font;button.accessibilityLabel=label;button.enabled=!self.questionSubmitted;
            CGFloat height=ceil([label boundingRectWithSize:CGSizeMake(available,CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin|NSStringDrawingUsesFontLeading attributes:@{NSFontAttributeName:font} context:nil].size.height)+24;[button.heightAnchor constraintGreaterThanOrEqualToConstant:MAX(44,height)].active=YES;
            [button addAction:[UIAction actionWithHandler:^(UIAction *action){PCChatTimeline *timeline=owner;if(!timeline||timeline.questionSubmitted||![timeline.pendingQuestion[@"id"] isEqual:prompt]||![timeline.pendingQuestion[@"job_id"] isEqual:job])return;BOOL sent=timeline.answerQuestion&&timeline.answerQuestion(job,prompt,answer);timeline.questionSubmitted=sent;timeline.questionSendError=sent?nil:PCLocalized(@"未能发送，请确认当前问题后重试。");[timeline rebuildMessages];}] forControlEvents:UIControlEventTouchUpInside];[stack addArrangedSubview:button];
        }
        UILabel *hint=[UILabel new];hint.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];hint.textColor=self.questionSendError?PCDangerColor():PCMutedColor();hint.numberOfLines=0;hint.text=self.questionSendError?:self.questionSubmitted?PCLocalized(@"等待 AI 继续…"):rootQuestion?PCLocalized(@"选择后执行上面的操作；自动执行工具不会跳过 Root 授权。"):options.count?PCLocalized(@"也可以在下方输入回答。"):PCLocalized(@"请在下方输入回答。");[stack addArrangedSubview:hint];
    }
    [cell.contentView addSubview:bubble]; [bubble addSubview:stack]; CGFloat inset = user||detail||question ? 14 : 4;
    [NSLayoutConstraint activateConstraints:@[[bubble.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:6], [bubble.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-10], [bubble.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16], [bubble.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:user?60:16], [stack.topAnchor constraintEqualToAnchor:bubble.topAnchor constant:inset], [stack.bottomAnchor constraintEqualToAnchor:bubble.bottomAnchor constant:-inset], [stack.leadingAnchor constraintEqualToAnchor:bubble.leadingAnchor constant:inset], [stack.trailingAnchor constraintEqualToAnchor:bubble.trailingAnchor constant:-inset]]];
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *item = self.messages[indexPath.row]; if ([item[@"detail"] boolValue] && self.showDetails) self.showDetails(item[@"kind"],item[@"body"]);
}
- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point {
    NSString *text = self.messages[indexPath.row][@"body"];
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu *(NSArray *actions) {
        return [UIMenu menuWithTitle:@"" children:@[[UIAction actionWithTitle:PCLocalized(@"复制") image:[UIImage systemImageNamed:@"doc.on.doc"] identifier:nil handler:^(UIAction *action) { UIPasteboard.generalPasteboard.string = text; }]]];
    }];
}
- (CGFloat)latestOffset {
    CGFloat bottom=MAX(-self.adjustedContentInset.top,self.contentSize.height-self.bounds.size.height+self.adjustedContentInset.bottom);
    if(self.pendingQuestion&&self.messages.count&&[self.messages.lastObject[@"question"] boolValue]){CGRect card=[self rectForRowAtIndexPath:[NSIndexPath indexPathForRow:self.messages.count-1 inSection:0]];if(card.size.height>self.bounds.size.height-self.adjustedContentInset.top-self.adjustedContentInset.bottom)return MAX(-self.adjustedContentInset.top,MIN(bottom,card.origin.y-12));}
    return bottom;
}
- (void)jumpToLatest {
    self.automaticFollow = YES;
    [self layoutIfNeeded]; CGFloat bottom = [self latestOffset]; [self setContentOffset:CGPointMake(0,bottom) animated:NO];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    if(self.pendingQuestion&&fabs(self.questionLayoutWidth-self.bounds.size.width)>1){self.questionLayoutWidth=self.bounds.size.width;[self reloadData];}
    // Self-sizing cells can resolve after reloadData's first layout pass.
    // Follow every resolved content-size / keyboard change, not just the estimate.
    if(!self.automaticFollow||self.dragging||self.decelerating||self.adjustingOffset)return;
    CGFloat bottom=[self latestOffset];
    if(fabs(self.contentOffset.y-bottom)>0.5){self.adjustingOffset=YES;[self setContentOffset:CGPointMake(0,bottom) animated:NO];self.adjustingOffset=NO;}
}
- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (!self.dragging && !self.decelerating) return;
    // Let a user scroll an oversized question all the way to its choices.
    if(self.pendingQuestion){self.automaticFollow=NO;if(self.followChanged)self.followChanged(NO);return;}
    CGFloat bottom = MAX(-self.adjustedContentInset.top,self.contentSize.height-self.bounds.size.height+self.adjustedContentInset.bottom);
    self.automaticFollow=self.contentOffset.y >= bottom-30;
    if (self.followChanged) self.followChanged(self.automaticFollow);
}
@end

@interface PCSidebarPresentation : UIPresentationController
@property(nonatomic,strong) UIView *shade;
@end
@implementation PCSidebarPresentation
- (CGRect)frameOfPresentedViewInContainerView { CGRect b=self.containerView.bounds;return CGRectMake(0,0,MIN(360,b.size.width*0.88),b.size.height); }
- (void)presentationTransitionWillBegin {
    self.shade = [[UIView alloc] initWithFrame:self.containerView.bounds]; self.shade.backgroundColor=[UIColor colorWithWhite:0 alpha:0.42];self.shade.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [self.shade addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(close)]];[self.containerView insertSubview:self.shade atIndex:0];
}
- (void)close { [self.presentedViewController dismissViewControllerAnimated:YES completion:nil]; }
- (void)containerViewWillLayoutSubviews { self.presentedView.frame=[self frameOfPresentedViewInContainerView]; }
- (void)dismissalTransitionDidEnd:(BOOL)completed { if(completed)[self.shade removeFromSuperview]; }
@end
@implementation PCSidebarTransition
- (UIPresentationController *)presentationControllerForPresentedViewController:(UIViewController *)presented presentingViewController:(UIViewController *)presenting sourceViewController:(UIViewController *)source { return [[PCSidebarPresentation alloc] initWithPresentedViewController:presented presentingViewController:presenting]; }
- (id<UIViewControllerAnimatedTransitioning>)animationControllerForPresentedController:(UIViewController *)presented presentingController:(UIViewController *)presenting sourceController:(UIViewController *)source { return self; }
- (id<UIViewControllerAnimatedTransitioning>)animationControllerForDismissedController:(UIViewController *)dismissed { return self; }
- (NSTimeInterval)transitionDuration:(id<UIViewControllerContextTransitioning>)context { return 0.25; }
- (void)animateTransition:(id<UIViewControllerContextTransitioning>)context {
    UIViewController *to=[context viewControllerForKey:UITransitionContextToViewControllerKey]; BOOL showing=to.isBeingPresented; UIView *view=[context viewForKey:showing?UITransitionContextToViewKey:UITransitionContextFromViewKey];
    if(showing){view.frame=[context finalFrameForViewController:to];[context.containerView addSubview:view];view.transform=CGAffineTransformMakeTranslation(-view.bounds.size.width,0);}
    [UIView animateWithDuration:0.25 animations:^{view.transform=showing?CGAffineTransformIdentity:CGAffineTransformMakeTranslation(-view.bounds.size.width,0);} completion:^(BOOL finished){[context completeTransition:!context.transitionWasCancelled];}];
}
@end
