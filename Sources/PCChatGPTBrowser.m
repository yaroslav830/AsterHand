#import "PCLocalization.h"
#import "PCChatGPTBrowser.h"
#import <SafariServices/SafariServices.h>
#import <WebKit/WebKit.h>
#import "PCOAuthTrace.h"

@interface PCChatGPTBrowserController () <SFSafariViewControllerDelegate,WKNavigationDelegate,WKUIDelegate>
@property(nonatomic,strong) NSURL *authorizationURL,*callbackURL;
@property(nonatomic,copy) dispatch_block_t cancelHandler;
@property(nonatomic,strong) SFSafariViewController *safari;
@property(nonatomic,strong) WKWebView *webView;
@property(nonatomic,strong) UILabel *statusLabel,*messageLabel;
@property(nonatomic,strong) UIButton *browserButton,*compatibilityButton,*registrationButton;
@property(nonatomic,strong) UIProgressView *progress;
@property(nonatomic) NSUInteger loadGeneration;
@property(nonatomic) BOOL callbackSubmitted;
@property(nonatomic) BOOL holdsIdleTimer,previousIdleTimerDisabled;
@property(nonatomic,strong) NSTimer *healthTimer;
@property(nonatomic) NSUInteger healthEventIndex;
@property(nonatomic,strong) NSMutableArray<WKWebView *> *popupViews;
@end

@implementation PCChatGPTBrowserController
- (instancetype)initWithURL:(NSURL *)url callbackURL:(NSURL *)callbackURL cancelHandler:(dispatch_block_t)cancelHandler {
    if((self=[super init])){_authorizationURL=url;_callbackURL=callbackURL;_cancelHandler=[cancelHandler copy];}return self;
}
- (UIButton *)button:(NSString *)title action:(SEL)action {
    UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];[button setTitle:title forState:UIControlStateNormal];button.titleLabel.font=[UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];[button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];return button;
}
- (void)viewDidLoad {
    [super viewDidLoad];self.title=PCLocalized(@"ChatGPT 登录");self.view.backgroundColor=UIColor.systemBackgroundColor;
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:PCLocalized(@"取消") style:UIBarButtonItemStylePlain target:self action:@selector(cancelSignIn)];
    self.navigationItem.rightBarButtonItems=@[[[UIBarButtonItem alloc] initWithTitle:@"Safari" style:UIBarButtonItemStylePlain target:self action:@selector(openSafari)],[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(retry)]];
    self.statusLabel=[UILabel new];self.statusLabel.font=[UIFont systemFontOfSize:13];self.statusLabel.textColor=UIColor.secondaryLabelColor;self.statusLabel.textAlignment=NSTextAlignmentCenter;self.statusLabel.text=PCLocalized(@"由 OpenAI 页面完成登录");
    self.progress=[[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleBar];self.progress.hidden=YES;
    self.messageLabel=[UILabel new];self.messageLabel.numberOfLines=0;self.messageLabel.textAlignment=NSTextAlignmentCenter;self.messageLabel.textColor=UIColor.secondaryLabelColor;self.messageLabel.text=PCLocalized(@"选择登录方式。页面空白或无法点击时，可尝试兼容模式。");
    self.browserButton=[self button:PCLocalized(@"系统浏览器登录") action:@selector(openSafari)];self.compatibilityButton=[self button:PCLocalized(@"兼容模式登录") action:@selector(openCompatibility)];
    self.registrationButton=[self button:PCLocalized(@"重新选择账户或工作区") action:@selector(newRegistration)];self.registrationButton.hidden=!self.newRegistrationHandler;
    UIStackView *actions=[[UIStackView alloc] initWithArrangedSubviews:@[self.messageLabel,self.browserButton,self.compatibilityButton,self.registrationButton]];actions.axis=UILayoutConstraintAxisVertical;actions.spacing=16;
    for(UIView *view in @[self.statusLabel,self.progress,actions]){view.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:view];}
    [NSLayoutConstraint activateConstraints:@[[self.statusLabel.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],[self.statusLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12],[self.statusLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12],[self.statusLabel.heightAnchor constraintEqualToConstant:24],[self.progress.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:4],[self.progress.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],[self.progress.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],[actions.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],[actions.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:32],[actions.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-32]]];
}
- (void)releaseLoginIdleTimer {
    if(!self.holdsIdleTimer)return;
    self.holdsIdleTimer=NO;UIApplication.sharedApplication.idleTimerDisabled=self.previousIdleTimerDisabled;
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if(!self.holdsIdleTimer){
        self.previousIdleTimerDisabled=UIApplication.sharedApplication.idleTimerDisabled;
        self.holdsIdleTimer=YES;UIApplication.sharedApplication.idleTimerDisabled=YES;
        // Match the bounded OAuth attempt; never leave an unattended screen awake indefinitely.
        __weak typeof(self) weakSelf=self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,600*NSEC_PER_SEC),dispatch_get_main_queue(),^{[weakSelf releaseLoginIdleTimer];});
    }
}
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    if(self.isBeingDismissed||self.navigationController.isBeingDismissed)[self releaseLoginIdleTimer];
}
- (void)cancelSignIn {[self releaseLoginIdleTimer];if(self.cancelHandler)self.cancelHandler();}
- (void)newRegistration {
    if(self.callbackSubmitted||!self.newRegistrationHandler)return;
    self.registrationButton.enabled=NO;[self.webView stopLoading];self.loadGeneration++;
    self.newRegistrationHandler();
}
- (void)showMessage:(NSString *)text {
    self.messageLabel.text=text;self.messageLabel.superview.hidden=NO;
}
- (void)openSafari {
    if(self.presentedViewController||self.isBeingDismissed)return;
    while(self.popupViews.count)[self closePopup];
    PCOAuthTrace(@"system_browser_opened");
    self.loadGeneration++;[self.webView stopLoading];self.webView.hidden=YES;self.progress.hidden=YES;[self showMessage:PCLocalized(@"请在 OpenAI 页面登录并确认授权。网页空白时，可点“完成”返回并选择兼容模式。")];
    SFSafariViewController *browser=[[SFSafariViewController alloc] initWithURL:self.authorizationURL];browser.delegate=self;browser.dismissButtonStyle=SFSafariViewControllerDismissButtonStyleDone;browser.modalPresentationStyle=UIModalPresentationFullScreen;self.safari=browser;[self presentViewController:browser animated:YES completion:nil];
}
- (void)safariViewControllerDidFinish:(SFSafariViewController *)controller {
    [controller dismissViewControllerAnimated:YES completion:^{self.safari=nil;[self showMessage:PCLocalized(@"登录尚未完成，可继续浏览器登录；页面空白或加载异常时，请尝试兼容模式。")];}];
}
- (void)safariViewController:(SFSafariViewController *)controller didCompleteInitialLoad:(BOOL)didLoadSuccessfully {
    if(!didLoadSuccessfully)[controller dismissViewControllerAnimated:YES completion:^{self.safari=nil;[self showMessage:PCLocalized(@"系统浏览器未能打开登录网页。请检查网络后重试，或选择兼容模式。")];}];
}
- (void)openCompatibility {
    if(self.presentedViewController)return;
    PCOAuthTrace(@"compatibility_browser_opened");
    if(!self.webView){
        WKWebViewConfiguration *configuration=[WKWebViewConfiguration new];configuration.websiteDataStore=WKWebsiteDataStore.nonPersistentDataStore;
        NSString *path=[NSBundle.mainBundle pathForResource:@"chatgpt-login-compat" ofType:@"js"];
        NSString *script=path?[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil]:nil;
        NSOperatingSystemVersion os=NSProcessInfo.processInfo.operatingSystemVersion;
        if(script.length&&(os.majorVersion<15||(os.majorVersion==15&&os.minorVersion<4)))script=[@"window.__asterHandLegacyCSP=true;\n" stringByAppendingString:script?:@""];
        NSString *streamsPath=[NSBundle.mainBundle pathForResource:@"chatgpt-login-streams" ofType:@"js"];
        NSString *streams=streamsPath?[NSString stringWithContentsOfFile:streamsPath encoding:NSUTF8StringEncoding error:nil]:nil;
        NSString *formsPath=[NSBundle.mainBundle pathForResource:@"chatgpt-login-forms" ofType:@"js"];
        NSString *forms=formsPath?[NSString stringWithContentsOfFile:formsPath encoding:NSUTF8StringEncoding error:nil]:nil;
        if(!script.length||!streams.length||!forms.length){[self showMessage:PCLocalized(@"登录兼容组件缺失，请重新安装应用。")];return;}
        [configuration.userContentController addUserScript:[[WKUserScript alloc] initWithSource:streams injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO]];
        [configuration.userContentController addUserScript:[[WKUserScript alloc] initWithSource:forms injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO]];
        [configuration.userContentController addUserScript:[[WKUserScript alloc] initWithSource:script injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO]];
        self.webView=[[WKWebView alloc] initWithFrame:CGRectZero configuration:configuration];self.webView.navigationDelegate=self;self.webView.UIDelegate=self;self.webView.translatesAutoresizingMaskIntoConstraints=NO;
        [self.view insertSubview:self.webView belowSubview:self.messageLabel.superview];
        [NSLayoutConstraint activateConstraints:@[[self.webView.topAnchor constraintEqualToAnchor:self.progress.bottomAnchor constant:4],[self.webView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],[self.webView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],[self.webView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor]]];
    }
    self.webView.hidden=NO;self.messageLabel.superview.hidden=YES;[self retry];
    if(!self.healthTimer){__weak typeof(self) weakSelf=self;self.healthTimer=[NSTimer scheduledTimerWithTimeInterval:2 repeats:YES block:^(NSTimer *timer){[weakSelf readCompatibilityHealth];}];}
}
- (void)readCompatibilityHealth {
    if(self.webView.hidden||![self.webView.URL.host.lowercaseString isEqual:@"auth.openai.com"])return;
    [self.webView evaluateJavaScript:@"window.__asterHandLoginHealth ? window.__asterHandLoginHealth.slice(0,80) : []" completionHandler:^(id events,NSError *error){
        if(error||![events isKindOfClass:NSArray.class])return;
        if([events count]<self.healthEventIndex)self.healthEventIndex=0;
        for(NSUInteger i=self.healthEventIndex;i<[events count];i++){
            NSString *event=events[i];if(![event isKindOfClass:NSString.class]||event.length>200)continue;
            NSRegularExpression *allowed=[NSRegularExpression regularExpressionWithPattern:@"^(csp_script_blocked_(sentinel|chatgpt|authcdn|other)|login_sdk_(ready|primary_failed|all_failed)|script_load_failed_(auth|authcdn|sentinel|chatgpt|other)|legacy_script_nonce|legacy_user_timing_return|legacy_form_submitter|js_asset_(auth|authcdn|static)_[A-Za-z0-9_-]{1,139}_line_[0-9]+_column_[0-9]+|js_stack_(missing|unmapped)|web_(reference|type|syntax|network|security|abort|unknown|cross_origin)_error|web_(module_import_failed|readonly_assignment|invalid_receiver)|js_(reference|method)_[a-z_][a-z0-9_]{0,48}|js_expression_[a-z_][a-z0-9_]{0,65}|react_(hydrated|not_hydrated)|missing_(url_parse|promise_resolvers|structured_clone|array_sorted|array_reversed|array_last|object_hasown|crypto_uuid|set_union|abort_timeout|abort_any)|fetch_(get|post|other)_([0-5]?[0-9]?[0-9]|failed))$" options:0 error:nil];
            if([allowed numberOfMatchesInString:event options:0 range:NSMakeRange(0,event.length)])PCOAuthTrace(event);
        }
        self.healthEventIndex=[events count];
    }];
}
- (void)retry {
    if(self.callbackSubmitted)return;if(self.popupViews.count){[self.popupViews.lastObject reload];return;}if(self.webView&&!self.webView.hidden){[self.webView loadRequest:[NSURLRequest requestWithURL:self.authorizationURL cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:45]];}else [self openSafari];
}
- (BOOL)navigationAllowed:(NSURL *)url {
    if([url.scheme.lowercaseString isEqual:@"https"])return YES;
    if([url.scheme.lowercaseString isEqual:@"about"]&&[url.absoluteString isEqual:@"about:blank"])return YES;
    return [url.scheme.lowercaseString isEqual:@"http"]&&[url.host isEqual:self.callbackURL.host]&&[url.port isEqual:self.callbackURL.port]&&[url.path isEqual:self.callbackURL.path];
}
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)action decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *url=action.request.URL;
    NSString *host=url.host.lowercaseString;NSString *destination=[host isEqual:@"auth.openai.com"]?@"openai":([host isEqual:@"accounts.google.com"]?@"google":([host hasSuffix:@"apple.com"]?@"apple":@"other"));
    if(!action.targetFrame||action.targetFrame.mainFrame)PCOAuthTrace([NSString stringWithFormat:@"navigation_%@_%@_%@",destination,[url.scheme.lowercaseString isEqual:@"https"]?@"https":@"other",[action.request.HTTPMethod isEqual:@"POST"]?@"post":@"get"]);
    if([url.scheme.lowercaseString isEqual:@"http"]&&[url.host isEqual:self.callbackURL.host]&&[url.port isEqual:self.callbackURL.port]&&[url.path isEqual:self.callbackURL.path]&&self.localCallback){decisionHandler(WKNavigationActionPolicyCancel);if(!self.callbackSubmitted){self.callbackSubmitted=YES;self.statusLabel.text=PCLocalized(@"正在验证登录授权…");for(UIBarButtonItem *item in self.navigationItem.rightBarButtonItems)item.enabled=NO;self.localCallback(url);}return;}
    BOOL allowed=[self navigationAllowed:action.request.URL];decisionHandler(allowed?WKNavigationActionPolicyAllow:WKNavigationActionPolicyCancel);
}
- (void)webView:(WKWebView *)webView decidePolicyForNavigationResponse:(WKNavigationResponse *)response decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler {
    if(response.forMainFrame&&[response.response isKindOfClass:NSHTTPURLResponse.class])PCOAuthTrace([NSString stringWithFormat:@"navigation_http_%ld",(long)[(NSHTTPURLResponse *)response.response statusCode]]);
    if(response.forMainFrame&&!response.canShowMIMEType)PCOAuthTrace(@"navigation_unrenderable_response");
    decisionHandler(WKNavigationResponsePolicyAllow);
}
- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration forNavigationAction:(WKNavigationAction *)action windowFeatures:(WKWindowFeatures *)features {
    if(action.targetFrame||(action.request.URL&&![self navigationAllowed:action.request.URL])||self.popupViews.count>=3)return nil;
    // Returning a real child with WebKit's configuration preserves window.opener,
    // the page's session, postMessage and window.close for federated sign-in.
    WKWebView *popup=[[WKWebView alloc] initWithFrame:CGRectZero configuration:configuration];
    popup.navigationDelegate=self;popup.UIDelegate=self;popup.translatesAutoresizingMaskIntoConstraints=NO;
    if(!self.popupViews)self.popupViews=[NSMutableArray new];[self.popupViews addObject:popup];
    [self.view insertSubview:popup belowSubview:self.messageLabel.superview];
    [NSLayoutConstraint activateConstraints:@[[popup.topAnchor constraintEqualToAnchor:self.progress.bottomAnchor constant:4],[popup.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],[popup.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],[popup.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor]]];
    self.navigationItem.leftBarButtonItems=@[self.navigationItem.leftBarButtonItems.firstObject?:self.navigationItem.leftBarButtonItem,[[UIBarButtonItem alloc] initWithTitle:PCLocalized(@"返回登录") style:UIBarButtonItemStylePlain target:self action:@selector(closePopup)]];
    PCOAuthTrace(@"login_popup_opened");return popup;
}
- (void)closePopup {
    WKWebView *popup=self.popupViews.lastObject;if(!popup)return;
    [popup stopLoading];popup.navigationDelegate=nil;popup.UIDelegate=nil;[popup removeFromSuperview];[self.popupViews removeLastObject];
    if(!self.popupViews.count)self.navigationItem.leftBarButtonItems=@[self.navigationItem.leftBarButtonItems.firstObject];
    PCOAuthTrace(@"login_popup_closed");
}
- (void)webViewDidClose:(WKWebView *)webView {
    if([self.popupViews containsObject:webView]){while(self.popupViews.count){BOOL last=self.popupViews.lastObject==webView;[self closePopup];if(last)break;}}
}
- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
    self.healthEventIndex=0;PCOAuthTrace(@"web_navigation_started");
    self.messageLabel.superview.hidden=YES;self.statusLabel.text=PCLocalized(@"正在连接 OpenAI…");self.progress.hidden=NO;self.progress.progress=.15;
    NSUInteger generation=++self.loadGeneration;__weak typeof(self) weakSelf=self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,15*NSEC_PER_SEC),dispatch_get_main_queue(),^{typeof(self) self=weakSelf;if(!self||self.loadGeneration!=generation||self.webView.hidden)return;self.statusLabel.text=PCLocalized(@"加载较慢，可刷新或切换 Safari");});
}
- (void)webView:(WKWebView *)webView didCommitNavigation:(WKNavigation *)navigation {self.progress.progress=.65;self.statusLabel.text=webView.URL.host?:PCLocalized(@"OpenAI 登录");}
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    self.loadGeneration++;self.progress.hidden=YES;self.statusLabel.text=webView.URL.host?:PCLocalized(@"OpenAI 登录");
    [webView evaluateJavaScript:@"document.body ? document.body.innerText.trim().length : 0" completionHandler:^(id count,NSError *error){if(!error&&[count isKindOfClass:NSNumber.class]&&[count integerValue]==0)self.statusLabel.text=PCLocalized(@"网页未显示内容，可刷新或切换 Safari");}];
    if([webView.URL.scheme.lowercaseString isEqual:@"https"]&&[webView.URL.host.lowercaseString isEqual:@"auth.openai.com"]){
        NSURL *loadedURL=webView.URL;
        // Return only a known error-code match; do not collect account or page text.
        [webView evaluateJavaScript:@"!!(document.body && document.body.innerText.indexOf('3p_login_workspace_scope_denied') !== -1)" completionHandler:^(id denied,NSError *error){
            if(error||![denied isKindOfClass:NSNumber.class]||![denied boolValue]||![webView.URL isEqual:loadedURL]||self.callbackSubmitted)return;
            self.statusLabel.text=PCLocalized(@"当前账户无权访问已绑定的工作区");
            self.webView.hidden=YES;
            [self showMessage:PCLocalized(@"OpenAI 拒绝了当前工作区的访问。可使用原工作区中的账户重试，或重新选择你有权使用的账户和工作区。")];
        }];
    }
}
- (void)failed:(NSError *)error {
    PCOAuthTrace([NSString stringWithFormat:@"web_navigation_error_%ld",(long)error.code]);
    if(error.code==NSURLErrorCancelled)return;self.loadGeneration++;self.progress.hidden=YES;self.statusLabel.text=PCLocalized(@"登录网页加载失败");[self showMessage:[NSString stringWithFormat:PCLocalized(@"%@（%ld）\n可刷新、重新打开浏览器，或切换兼容模式。"),error.localizedDescription?:PCLocalized(@"请检查网络"),(long)error.code]];
}
- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {[self failed:error];}
- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {[self failed:error];}
- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView {self.loadGeneration++;self.progress.hidden=YES;[self showMessage:PCLocalized(@"登录网页进程已退出。请重试，或切换 Safari 登录。")];}
- (void)dealloc {[self releaseLoginIdleTimer];[self.healthTimer invalidate];for(WKWebView *popup in self.popupViews){[popup stopLoading];popup.navigationDelegate=nil;popup.UIDelegate=nil;}[self.webView stopLoading];self.webView.navigationDelegate=nil;self.webView.UIDelegate=nil;}
@end

