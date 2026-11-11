#import "PCChatGPTAuth.h"
#import "PCChatGPTBrowser.h"
#import "PCOAuthListener.h"
#import "PCOAuthTrace.h"
#import "PCSupport.h"
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <Security/Security.h>
#import <CommonCrypto/CommonDigest.h>
#import <sys/socket.h>
#import <netinet/in.h>
#include <unistd.h>
#include <arpa/inet.h>

static NSData *PCBase64URLDecode(NSString *value) {
    NSString *s = [[value stringByReplacingOccurrencesOfString:@"-" withString:@"+"] stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
    while (s.length % 4) s = [s stringByAppendingString:@"="];
    return [[NSData alloc] initWithBase64EncodedString:s options:0];
}
static NSString *PCBase64URL(NSData *data) {
    NSString *s = [[data base64EncodedStringWithOptions:0] stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    s = [s stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    return [[s stringByReplacingOccurrencesOfString:@"=" withString:@""] copy];
}
static NSData *PCRandom(NSUInteger count) {
    NSMutableData *d = [NSMutableData dataWithLength:count];
    if (SecRandomCopyBytes(kSecRandomDefault, count, d.mutableBytes) != errSecSuccess) return nil;
    return d;
}
static NSString *PCFormEscape(NSString *s) {
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    return [s stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"";
}
@interface PCNoRedirect : NSObject <NSURLSessionTaskDelegate> @end
@implementation PCNoRedirect
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest *))completionHandler { completionHandler(nil); }
@end
static NSDictionary *PCSyncJSON(NSString *urlString, NSString *method, NSString *contentType, NSData *body, NSError **error) {
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url || ![url.scheme.lowercaseString isEqual:@"https"]) { if (error) *error = PCError(@"OAuth 请求地址无效，已拒绝发送凭据。"); return nil; }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = method; request.timeoutInterval = 30;
    if (contentType) [request setValue:contentType forHTTPHeaderField:@"Content-Type"];
    request.HTTPBody = body;
    NSURLSessionConfiguration *cfg = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    cfg.HTTPCookieStorage = nil; cfg.URLCache = nil;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg delegate:[PCNoRedirect new] delegateQueue:nil];
    __block NSData *result; __block NSHTTPURLResponse *response; __block NSError *failure;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [[session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *r, NSError *e) { result = data; response = (NSHTTPURLResponse *)r; failure = e; dispatch_semaphore_signal(sem); }] resume];
    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER); [session finishTasksAndInvalidate];
    NSString *kind=[url.path isEqual:@"/api/accounts/oauth/token"]?@"token":([url.path isEqual:@"/.well-known/openid-configuration"]?@"metadata":@"public_keys");
    PCOAuthTrace([NSString stringWithFormat:@"%@_http_%ld",kind,(long)response.statusCode]);
    if (failure) {
        PCOAuthTrace([NSString stringWithFormat:@"network_error_%ld",(long)failure.code]);
        if (error) *error = PCError(PCRedact([NSString stringWithFormat:@"连接 %@ 失败：%@", url.host ?: @"OAuth 服务", failure.localizedDescription ?: @"网络错误"]));
        return nil;
    }
    id json = result ? [NSJSONSerialization JSONObjectWithData:result options:0 error:nil] : nil;
    if (response.statusCode < 200 || response.statusCode >= 300 || ![json isKindOfClass:NSDictionary.class]) {
        NSString *message = [json isKindOfClass:NSDictionary.class] ? json[@"error_description"] ?: json[@"error"] : nil;
        if (![message isKindOfClass:NSString.class]) message = [NSString stringWithFormat:@"OAuth 服务请求失败（HTTP %ld）。", (long)response.statusCode];
        if (error) *error = PCError(PCRedact(message)); return nil;
    }
    return json;
}
static NSData *PCDERLength(NSUInteger n) {
    NSMutableData *d = [NSMutableData new];
    if (n < 128) { uint8_t b = (uint8_t)n; [d appendBytes:&b length:1]; }
    else { uint8_t bytes[sizeof(NSUInteger)]; NSUInteger count = 0, v = n; while (v) { bytes[sizeof(bytes)-1-count++] = (uint8_t)(v & 255); v >>= 8; }
        uint8_t marker = 0x80 | (uint8_t)count; [d appendBytes:&marker length:1]; [d appendBytes:bytes + sizeof(bytes)-count length:count]; }
    return d;
}
static NSData *PCDERWrap(uint8_t tag, NSData *data) { NSMutableData *d = [NSMutableData dataWithBytes:&tag length:1]; [d appendData:PCDERLength(data.length)]; [d appendData:data]; return d; }
static NSData *PCDERInteger(NSData *data) {
    const uint8_t *bytes = data.bytes; NSUInteger offset = 0; while (offset + 1 < data.length && bytes[offset] == 0) offset++;
    NSData *v = [data subdataWithRange:NSMakeRange(offset, data.length-offset)];
    if (((const uint8_t *)v.bytes)[0] & 0x80) { NSMutableData *p = [NSMutableData dataWithBytes:"\0" length:1]; [p appendData:v]; v = p; }
    return PCDERWrap(0x02, v);
}
static SecKeyRef PCCreateRSAKey(NSDictionary *jwk) {
    NSData *n = PCBase64URLDecode(jwk[@"n"]), *e = PCBase64URLDecode(jwk[@"e"]);
    if (!n.length || !e.length) return NULL;
    NSMutableData *pkcs1 = [NSMutableData new]; [pkcs1 appendData:PCDERInteger(n)]; [pkcs1 appendData:PCDERInteger(e)];
    NSData *sequence = PCDERWrap(0x30, pkcs1);
    NSDictionary *attrs = @{(__bridge id)kSecAttrKeyType:(__bridge id)kSecAttrKeyTypeRSA, (__bridge id)kSecAttrKeyClass:(__bridge id)kSecAttrKeyClassPublic,
                            (__bridge id)kSecAttrKeySizeInBits:@(n.length * 8)};
    return SecKeyCreateWithData((__bridge CFDataRef)sequence, (__bridge CFDictionaryRef)attrs, NULL);
}
static SecKeyRef PCCreateECKey(NSDictionary *jwk) {
    NSData *x = PCBase64URLDecode(jwk[@"x"]), *y = PCBase64URLDecode(jwk[@"y"]);
    if (!x.length || !y.length) return NULL;
    NSMutableData *point = [NSMutableData dataWithBytes:"\x04" length:1]; [point appendData:x]; [point appendData:y];
    NSDictionary *attrs = @{(__bridge id)kSecAttrKeyType:(__bridge id)kSecAttrKeyTypeECSECPrimeRandom, (__bridge id)kSecAttrKeyClass:(__bridge id)kSecAttrKeyClassPublic,
                            (__bridge id)kSecAttrKeySizeInBits:@(x.length * 8)};
    return SecKeyCreateWithData((__bridge CFDataRef)point, (__bridge CFDictionaryRef)attrs, NULL);
}
static NSDictionary *PCVerifyIDToken(NSString *token, NSString *clientID, NSString *nonce, NSError **error) {
    if(![token isKindOfClass:NSString.class]||!token.length){if(error)*error=PCError(@"OpenAI 未返回有效的身份凭据。");return nil;}
    NSArray *pieces = [token componentsSeparatedByString:@"."];
    if (pieces.count != 3) { if (error) *error = PCError(@"Sign in with ChatGPT 返回的 ID token 格式无效。"); return nil; }
    NSData *headerData = PCBase64URLDecode(pieces[0]), *claimData = PCBase64URLDecode(pieces[1]), *signature = PCBase64URLDecode(pieces[2]);
    NSDictionary *header = headerData.length?[NSJSONSerialization JSONObjectWithData:headerData options:0 error:nil]:nil;
    NSDictionary *claims = claimData.length?[NSJSONSerialization JSONObjectWithData:claimData options:0 error:nil]:nil;
    if (![header isKindOfClass:NSDictionary.class] || ![claims isKindOfClass:NSDictionary.class] || !signature.length) { if (error) *error = PCError(@"ID token 内容无法解析。"); return nil; }
    NSError *fetchError; NSDictionary *oidc = PCSyncJSON(@"https://auth.openai.com/.well-known/openid-configuration", @"GET", nil, nil, &fetchError);
    NSDictionary *jwks = oidc ? PCSyncJSON(oidc[@"jwks_uri"], @"GET", nil, nil, &fetchError) : nil;
    if (![oidc[@"jwks_uri"] isKindOfClass:NSString.class]) { if (error) *error = fetchError ?: PCError(@"OpenID 公钥服务地址无效。"); return nil; }
    NSDictionary *jwk = nil;
    for (NSDictionary *candidate in jwks[@"keys"]) if ([candidate[@"kid"] isEqual:header[@"kid"]]) { jwk = candidate; break; }
    NSString *alg = header[@"alg"];
    SecKeyRef key = [alg hasPrefix:@"RS"] ? PCCreateRSAKey(jwk) : ([alg hasPrefix:@"ES"] ? PCCreateECKey(jwk) : NULL);
    SecKeyAlgorithm algorithm = [alg isEqual:@"RS256"] ? kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256 :
        ([alg isEqual:@"ES256"] ? kSecKeyAlgorithmECDSASignatureMessageX962SHA256 : NULL);
    if ([alg isEqual:@"ES256"] && signature.length == 64) {
        NSData *r = [signature subdataWithRange:NSMakeRange(0,32)], *s = [signature subdataWithRange:NSMakeRange(32,32)];
        NSMutableData *parts = [NSMutableData new]; [parts appendData:PCDERInteger(r)]; [parts appendData:PCDERInteger(s)];
        signature = PCDERWrap(0x30, parts);
    }
    NSString *signedText = [NSString stringWithFormat:@"%@.%@", pieces[0], pieces[1]];
    BOOL signatureOK = key && algorithm && SecKeyIsAlgorithmSupported(key, kSecKeyOperationTypeVerify, algorithm) &&
        SecKeyVerifySignature(key, algorithm, (__bridge CFDataRef)[signedText dataUsingEncoding:NSUTF8StringEncoding], (__bridge CFDataRef)signature, NULL);
    if (key) CFRelease(key);
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    BOOL audOK = [claims[@"aud"] isEqual:clientID] || ([claims[@"aud"] isKindOfClass:NSArray.class] && [claims[@"aud"] containsObject:clientID]);
    BOOL valid = signatureOK && audOK && [claims[@"iss"] isEqual:oidc[@"issuer"]] && [claims[@"nonce"] isEqual:nonce] &&
        [claims[@"sub"] isKindOfClass:NSString.class] && [claims[@"exp"] respondsToSelector:@selector(doubleValue)] && [claims[@"exp"] doubleValue] > now;
    if (!valid) { if (error) *error = fetchError ?: PCError(@"ID token 签名、发行者、受众、nonce 或有效期校验失败，已拒绝保存登录信息。"); return nil; }
    return claims;
}
static NSString *PCQueryValue(NSString *query, NSString *name) {
    for (NSString *part in [query componentsSeparatedByString:@"&"]) {
        NSArray *pair = [part componentsSeparatedByString:@"="];
        NSString *key = [[pair.firstObject stringByReplacingOccurrencesOfString:@"+" withString:@" "] stringByRemovingPercentEncoding];
        if ([key isEqual:name] && pair.count > 1) return [[[pair subarrayWithRange:NSMakeRange(1, pair.count-1)] componentsJoinedByString:@"="] stringByReplacingOccurrencesOfString:@"+" withString:@" "].stringByRemovingPercentEncoding;
    }
    return nil;
}

static NSDictionary *PCManualOAuthAttempt;
static NSObject *PCManualOAuthLock(void) {
    static NSObject *lock; static dispatch_once_t once;
    dispatch_once(&once, ^{ lock = [NSObject new]; });
    return lock;
}
static BOOL PCManualCallbackMatches(NSURLComponents *parts) {
    return parts && [parts.scheme.lowercaseString isEqual:@"http"] && [parts.host isEqual:@"127.0.0.1"] && [parts.port isEqualToNumber:@54321] && [parts.path isEqual:@"/auth/callback"] && !parts.user && !parts.password && !parts.fragment;
}
static NSURLComponents *PCManualCallbackComponents(NSString *text) {
    NSString *value=[text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    // Some mobile browsers omit the scheme when copying the address bar.
    // Restore it only for the exact loopback host, port and callback path.
    if([value hasPrefix:@"127.0.0.1:54321/auth/callback?"])value=[@"http://" stringByAppendingString:value];
    return [NSURLComponents componentsWithString:value?:@""];
}
NSString *PCChatGPTPrepareDesktopAuthorizationURL(NSError **error) {
    NSDictionary *existing = PCChatGPTCredentials();
    NSString *host = [[NSUserDefaults standardUserDefaults] stringForKey:@"siwcHostID"];
    if (!host.length) { host = [@"urn:uuid:" stringByAppendingString:NSUUID.UUID.UUIDString.lowercaseString]; [[NSUserDefaults standardUserDefaults] setObject:host forKey:@"siwcHostID"]; }
    NSData *stateData = PCRandom(32), *nonceData = PCRandom(32), *verifierData = PCRandom(32);
    if (!stateData || !nonceData || !verifierData) { if (error) *error = PCError(@"无法生成安全的 OAuth 随机数。"); return nil; }
    NSString *state = PCBase64URL(stateData), *nonce = PCBase64URL(nonceData), *verifier = PCBase64URL(verifierData);
    uint8_t digest[CC_SHA256_DIGEST_LENGTH]; CC_SHA256(verifier.UTF8String, (CC_LONG)strlen(verifier.UTF8String), digest);
    NSString *challenge = PCBase64URL([NSData dataWithBytes:digest length:sizeof(digest)]);
    NSString *redirect = @"http://127.0.0.1:54321/auth/callback";
    NSString *clientID = [existing[@"client_id"] isKindOfClass:NSString.class] ? existing[@"client_id"] : @"dynamic_agent_client";
    NSDictionary *attempt = @{ @"state": state, @"nonce": nonce, @"verifier": verifier, @"redirect": redirect,
        @"client_id": clientID, @"host": host, @"created": NSDate.date };
    @synchronized (PCManualOAuthLock()) { PCManualOAuthAttempt = attempt; }
    NSMutableArray *query = [NSMutableArray new];
    NSDictionary *params = @{ @"client_id": clientID, @"response_type": @"code", @"redirect_uri": redirect,
        @"scope": @"openid profile email offline_access resource.invoke chatgpt.tokens.use.direct", @"resource": @"https://api.openai.com/v1",
        @"state": state, @"nonce": nonce, @"code_challenge_method": @"S256", @"code_challenge": challenge, @"ext_agent_host_id": host };
    for (NSString *key in params) [query addObject:[NSString stringWithFormat:@"%@=%@", PCFormEscape(key), PCFormEscape(params[key])]];
    if ([clientID isEqual:@"dynamic_agent_client"]) [query addObject:[@"agent_name_hint=" stringByAppendingString:PCFormEscape(@"AsterHand")]];
    // The authorization URL is displayed as a QR code: never embed a saved
    // ID token or email in it. A returning registration can select its account.
    return [NSString stringWithFormat:@"https://auth.openai.com/api/accounts/authorize?%@", [query componentsJoinedByString:@"&"]];
}

void PCChatGPTCompleteDesktopSignIn(NSString *callbackURL, void (^completion)(NSDictionary *, NSError *)) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *failure = nil; NSDictionary *credentials = nil; NSDictionary *attempt; BOOL attemptedExchange=NO;
        @synchronized (PCManualOAuthLock()) { attempt = PCManualOAuthAttempt; }
        if (![attempt isKindOfClass:NSDictionary.class] || [NSDate.date timeIntervalSinceDate:attempt[@"created"]] > 600) failure = PCError(@"授权请求已过期，请重新开始电脑浏览器登录。");
        NSURLComponents *parts = PCManualCallbackComponents(callbackURL ?: @"");
        if (!failure && !PCManualCallbackMatches(parts)) failure = PCError(@"回调地址不匹配。请粘贴浏览器地址栏中的完整回调链接。");
        NSMutableDictionary *values = [NSMutableDictionary new];
        for (NSURLQueryItem *item in parts.queryItems ?: @[]) if (item.name && item.value) {if(values[item.name]){failure=PCError(@"回调包含重复参数，请重新开始登录。");break;}values[item.name]=item.value;}
        if (!failure && ![values[@"state"] isEqual:attempt[@"state"]]) failure = PCError(@"OAuth state 不匹配，已拒绝回调。");
        if (!failure && values[@"error"]) failure = PCError(values[@"error_description"] ?: @"OpenAI 未完成授权。");
        NSString *code = values[@"code"];
        NSString *issuedID = values[@"client_id"];
        NSString *clientID = attempt[@"client_id"];
        if (!failure && !code.length) failure = PCError(@"回调地址中没有授权码。");
        if (!failure && [clientID isEqual:@"dynamic_agent_client"]) clientID = issuedID;
        else if (!failure && issuedID.length && ![issuedID isEqual:clientID]) failure = PCError(@"OAuth 返回了不匹配的 client_id。");
        if (!failure && !clientID.length) failure = PCError(@"OpenAI 没有返回已注册的 client_id。");
        if (!failure) {
            attemptedExchange=YES;
            NSDictionary *form = @{ @"grant_type": @"authorization_code", @"client_id": clientID, @"code": code,
                @"code_verifier": attempt[@"verifier"], @"redirect_uri": attempt[@"redirect"], @"resource": @"https://api.openai.com/v1" };
            NSMutableArray *pairs = [NSMutableArray new]; for (NSString *key in form) [pairs addObject:[NSString stringWithFormat:@"%@=%@", PCFormEscape(key), PCFormEscape(form[key])]];
            NSDictionary *token = PCSyncJSON(@"https://auth.openai.com/api/accounts/oauth/token", @"POST", @"application/x-www-form-urlencoded", [[pairs componentsJoinedByString:@"&"] dataUsingEncoding:NSUTF8StringEncoding], &failure);
            if(token&&(![token[@"access_token"] isKindOfClass:NSString.class]||![token[@"access_token"] length]||![token[@"refresh_token"] isKindOfClass:NSString.class]||![token[@"refresh_token"] length]||![token[@"id_token"] isKindOfClass:NSString.class]||![token[@"expires_in"] respondsToSelector:@selector(doubleValue)]||[token[@"expires_in"] doubleValue]<=0)){failure=PCError(@"授权服务没有返回完整的登录凭据。");token=nil;}
            NSDictionary *claims = token ? PCVerifyIDToken(token[@"id_token"], clientID, attempt[@"nonce"], &failure) : nil;
            NSDictionary *previous = PCChatGPTCredentials();
            if (claims && [previous[@"client_id"] isEqual:clientID] && [previous[@"sub"] length] && ![previous[@"sub"] isEqual:claims[@"sub"]]) failure = PCError(@"返回的 ChatGPT 账户与当前保存的账户不同，已保留原登录。");
            NSString *scopeString = [token[@"scope"] isKindOfClass:NSString.class] ? token[@"scope"] : (values[@"scope"] ?: @"");
            NSMutableSet *scopes = [NSMutableSet new]; for (NSString *scope in [scopeString componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet]) if (scope.length) [scopes addObject:scope];
            if (token && claims && ![scopes containsObject:@"chatgpt.tokens.use.direct"]) failure = PCError(@"已登录，但这次没有授权 ChatGPT 套餐用量。请重新开始并在 OpenAI 页面确认该权限。");
            if (token && claims && !failure) {
                credentials = @{ @"client_id": clientID, @"ext_agent_host_id": attempt[@"host"], @"access_token": token[@"access_token"] ?: @"",
                    @"refresh_token": token[@"refresh_token"] ?: @"", @"id_token": token[@"id_token"] ?: @"",
                    @"expires_at": @(NSDate.date.timeIntervalSince1970 + [token[@"expires_in"] doubleValue]), @"scope": [scopes.allObjects componentsJoinedByString:@" "],
                    @"sub": claims[@"sub"] ?: @"", @"email": claims[@"email"] ?: @"" };
                @synchronized (PCManualOAuthLock()) {if(PCManualOAuthAttempt!=attempt){failure=PCError(@"登录请求已更新，请重新开始。");credentials=nil;}else if(!PCSetChatGPTCredentials(credentials, &failure)) credentials=nil;}
            }
        }
        @synchronized (PCManualOAuthLock()) { if(attemptedExchange && PCManualOAuthAttempt==attempt) PCManualOAuthAttempt = nil; }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(credentials, failure); });
    });
}

static UIViewController *PCChatGPTPresentationController(void) {
    UIWindow *window = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *candidate in ((UIWindowScene *)scene).windows) if (candidate.isKeyWindow) { window = candidate; break; }
        if (window) break;
    }
    UIViewController *controller = window.rootViewController;
    while (controller.presentedViewController && !controller.presentedViewController.isBeingDismissed) controller = controller.presentedViewController;
    if ([controller isKindOfClass:UINavigationController.class]) controller = ((UINavigationController *)controller).visibleViewController;
    if ([controller isKindOfClass:UITabBarController.class]) controller = ((UITabBarController *)controller).selectedViewController;
    return controller;
}

static NSString *PCRegistrationClient(NSDictionary *existing,NSString *pending,BOOL newRegistration) {
    if(newRegistration)return @"dynamic_agent_client";
    NSString *client=[existing[@"client_id"] isKindOfClass:NSString.class]?existing[@"client_id"]:nil;
    if(client.length&&![client isEqual:@"dynamic_agent_client"])return client;
    return pending.length&&![pending isEqual:@"dynamic_agent_client"]?pending:@"dynamic_agent_client";
}
static NSDictionary *PCRegistrationParameters(NSDictionary *existing,NSString *client,NSString *host,NSString *redirect,NSString *state,NSString *nonce,NSString *challenge) {
    NSMutableDictionary *params=[@{@"client_id":client,@"response_type":@"code",@"redirect_uri":redirect,
        @"scope":@"openid profile email offline_access resource.invoke chatgpt.tokens.use.direct",@"resource":@"https://api.openai.com/v1",
        @"state":state,@"nonce":nonce,@"code_challenge_method":@"S256",@"code_challenge":challenge,@"ext_agent_host_id":host} mutableCopy];
    if([client isEqual:@"dynamic_agent_client"])params[@"agent_name_hint"]=@"AsterHand";
    else if([existing[@"client_id"] isEqual:client]){
        if([existing[@"id_token"] isKindOfClass:NSString.class]&&[existing[@"id_token"] length])params[@"id_token_hint"]=existing[@"id_token"];
        if([existing[@"email"] isKindOfClass:NSString.class]&&[existing[@"email"] length])params[@"login_hint"]=existing[@"email"];
    }
    return params;
}
NSDictionary *PCChatGPTAuthorizationSelfTest(void) {
    NSDictionary *old=@{@"client_id":@"oaiapp_old",@"sub":@"fixture-user",@"id_token":@"fixture-token",@"email":@"fixture@example.invalid"};
    NSDictionary *(^params)(BOOL)=^NSDictionary *(BOOL fresh){return PCRegistrationParameters(old,PCRegistrationClient(old,@"oaiapp_pending",fresh),@"urn:uuid:fixture",@"http://127.0.0.1:12345/auth/callback",@"fixture-state",@"fixture-nonce",@"fixture-challenge");};
    NSDictionary *normal=params(NO),*fresh=params(YES);
    NSDictionary *pending=PCRegistrationParameters(nil,PCRegistrationClient(nil,@"oaiapp_pending",NO),@"urn:uuid:fixture",@"http://127.0.0.1:12345/auth/callback",@"fixture-state",@"fixture-nonce",@"fixture-challenge");
    return @{@"oauth_registration_reuses_verified_account":@([normal[@"client_id"] isEqual:@"oaiapp_old"]&&[normal[@"id_token_hint"] isEqual:@"fixture-token"]&&!normal[@"agent_name_hint"]),
        @"oauth_qr_callback_accepts_numeric_port":@(PCManualCallbackMatches([NSURLComponents componentsWithString:@"http://127.0.0.1:54321/auth/callback?code=fixture&state=fixture"])),
        @"oauth_qr_callback_accepts_browser_copy_without_scheme":@(PCManualCallbackMatches(PCManualCallbackComponents(@"127.0.0.1:54321/auth/callback?code=fixture&state=fixture"))),
        @"oauth_qr_callback_rejects_bare_wrong_host":@(!PCManualCallbackMatches(PCManualCallbackComponents(@"127.0.0.2:54321/auth/callback?code=fixture&state=fixture"))),
        @"oauth_qr_callback_rejects_wrong_port_and_userinfo":@(!PCManualCallbackMatches([NSURLComponents componentsWithString:@"http://127.0.0.1:54322/auth/callback?code=fixture"])&&!PCManualCallbackMatches([NSURLComponents componentsWithString:@"http://user@127.0.0.1:54321/auth/callback?code=fixture"])),
        @"oauth_registration_pending_client_retained_for_retry":@([pending[@"client_id"] isEqual:@"oaiapp_pending"]&&!pending[@"id_token_hint"]&&!pending[@"login_hint"]),
        @"oauth_registration_switch_uses_fresh_client_without_account_hints":@([fresh[@"client_id"] isEqual:@"dynamic_agent_client"]&&[fresh[@"agent_name_hint"] isEqual:@"AsterHand"]&&!fresh[@"id_token_hint"]&&!fresh[@"login_hint"]&&[fresh[@"ext_agent_host_id"] isEqual:normal[@"ext_agent_host_id"]]&&[old[@"client_id"] isEqual:@"oaiapp_old"]),
        @"oauth_registration_empty_client_uses_initial_flow":@([PCRegistrationClient(@{@"client_id":@""},nil,NO) isEqual:@"dynamic_agent_client"])};
}
static void PCChatGPTStartSignIn(BOOL newRegistration,void (^completion)(NSDictionary *, NSError *)) {
    dispatch_async(dispatch_get_main_queue(), ^{
        PCOAuthTraceBegin();
        NSDictionary *existing = PCChatGPTCredentials();
        NSString *host = [[NSUserDefaults standardUserDefaults] stringForKey:@"siwcHostID"];
        if (!host.length) { host = [@"urn:uuid:" stringByAppendingString:NSUUID.UUID.UUIDString.lowercaseString]; [[NSUserDefaults standardUserDefaults] setObject:host forKey:@"siwcHostID"]; }
        NSData *stateData = PCRandom(32), *nonceData = PCRandom(32), *verifierData = PCRandom(32);
        if (!stateData || !nonceData || !verifierData) { completion(nil, PCError(@"无法生成安全的 OAuth 随机数。")); return; }
        NSString *state = PCBase64URL(stateData), *nonce = PCBase64URL(nonceData), *verifier = PCBase64URL(verifierData);
        uint8_t digest[CC_SHA256_DIGEST_LENGTH]; CC_SHA256(verifier.UTF8String, (CC_LONG)strlen(verifier.UTF8String), digest);
        NSString *challenge = PCBase64URL([NSData dataWithBytes:digest length:sizeof(digest)]);
        int listener = socket(AF_INET, SOCK_STREAM, 0);
        struct sockaddr_in addr = {0}; addr.sin_len = sizeof(addr); addr.sin_family = AF_INET; addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK); addr.sin_port = 0;
        if (listener < 0 || bind(listener, (struct sockaddr *)&addr, sizeof(addr)) || listen(listener, 1)) { if (listener >= 0) close(listener); completion(nil, PCError(@"无法开启本地 OAuth 回调。")); return; }
        socklen_t addrLen = sizeof(addr); getsockname(listener, (struct sockaddr *)&addr, &addrLen);
        NSString *redirect = [NSString stringWithFormat:@"http://127.0.0.1:%d/auth/callback", ntohs(addr.sin_port)];
        PCOAuthTrace(@"listener_ready");
        NSString *pendingClientID = [[NSUserDefaults standardUserDefaults] stringForKey:@"siwcPendingClientID"];
        NSString *clientID = PCRegistrationClient(existing,pendingClientID,newRegistration);
        PCOAuthTrace([clientID isEqual:@"dynamic_agent_client"]?@"initial_registration":@"issued_client_reauthorization");
        NSMutableArray *query = [NSMutableArray new];
        NSDictionary *params=PCRegistrationParameters(existing,clientID,host,redirect,state,nonce,challenge);
        for (NSString *k in params) [query addObject:[NSString stringWithFormat:@"%@=%@", PCFormEscape(k), PCFormEscape(params[k])]];
        NSURL *authorize = [NSURL URLWithString:[NSString stringWithFormat:@"https://auth.openai.com/api/accounts/authorize?%@", [query componentsJoinedByString:@"&"]]];
        NSObject *attemptLock=[NSObject new];__block BOOL cancelled=NO,restartRegistration=NO;
        UIBackgroundTaskIdentifier bg = [UIApplication.sharedApplication beginBackgroundTaskWithExpirationHandler:^{PCOAuthTrace(@"background_time_expired");@synchronized(attemptLock){cancelled=YES;}shutdown(listener,SHUT_RDWR);}];
        __block __weak UINavigationController *weakNavigation = nil;
        __block dispatch_once_t completionGuard = 0;
        void (^finish)(NSDictionary *, NSError *) = ^(NSDictionary *credentials, NSError *failure) {
            dispatch_once(&completionGuard, ^{
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (bg != UIBackgroundTaskInvalid) [UIApplication.sharedApplication endBackgroundTask:bg];
                    UINavigationController *navigation=weakNavigation;UIViewController *owner=navigation.presentingViewController;
                    void (^deliver)(void)=^{BOOL restart;@synchronized(attemptLock){restart=restartRegistration;}if(restart)PCChatGPTStartSignIn(YES,completion);else completion(credentials,failure);};
                    if(owner&&owner.presentedViewController==navigation)[owner dismissViewControllerAnimated:YES completion:deliver];else deliver();
                });
            });
        };
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSError *authError=nil;NSDictionary *credentials=nil;
            NSDictionary *callback=PCOAuthWaitForCallback(listener,[NSURL URLWithString:redirect],state,600,&authError);
            close(listener);
            PCOAuthTrace(callback?@"callback_received":@"callback_wait_ended");
            if(callback[@"error"])authError=PCError(callback[@"error_description"]?:@"OpenAI 未完成授权。");
            if(callback&&!authError){
                NSString *code=callback[@"code"],*issuedID=callback[@"client_id"];
                NSString *exchangeID=[clientID isEqual:@"dynamic_agent_client"]?issuedID:clientID;
                if(!exchangeID.length||(![clientID isEqual:@"dynamic_agent_client"]&&issuedID.length&&![issuedID isEqual:clientID]))authError=PCError(@"OAuth 返回了无效的 client_id。");
                else {
                    if([clientID isEqual:@"dynamic_agent_client"])[NSUserDefaults.standardUserDefaults setObject:exchangeID forKey:@"siwcPendingClientID"];
                    NSDictionary *form=@{@"grant_type":@"authorization_code",@"client_id":exchangeID,@"code":code,@"code_verifier":verifier,@"redirect_uri":redirect,@"resource":@"https://api.openai.com/v1"};
                    NSMutableArray *pairs=[NSMutableArray new];for(NSString *k in form)[pairs addObject:[NSString stringWithFormat:@"%@=%@",PCFormEscape(k),PCFormEscape(form[k])]];
                    NSDictionary *token=PCSyncJSON(@"https://auth.openai.com/api/accounts/oauth/token",@"POST",@"application/x-www-form-urlencoded",[[pairs componentsJoinedByString:@"&"] dataUsingEncoding:NSUTF8StringEncoding],&authError);
                    PCOAuthTrace(token?@"token_received":@"token_exchange_failed");
                    if(token&&(![token[@"access_token"] isKindOfClass:NSString.class]||![token[@"refresh_token"] isKindOfClass:NSString.class]||![token[@"id_token"] isKindOfClass:NSString.class])){authError=PCError(@"OAuth 响应缺少必要的访问或刷新凭据。");token=nil;}
                    NSDictionary *claims=token?PCVerifyIDToken(token[@"id_token"],exchangeID,nonce,&authError):nil;
                    if(token)PCOAuthTrace(claims?@"identity_verified":@"identity_verification_failed");
                    if(claims&&[existing[@"client_id"] isEqual:exchangeID]&&[existing[@"sub"] length]&&![existing[@"sub"] isEqual:claims[@"sub"]])authError=PCError(@"返回的 ChatGPT 账户与原账户不同，已保留原登录。");
                    NSString *scopeString=[token[@"scope"] isKindOfClass:NSString.class]?token[@"scope"]:@"";
                    NSMutableSet *scopes=[NSMutableSet new];for(NSString *scope in [scopeString componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet])if(scope.length)[scopes addObject:scope];
                    if(token&&claims&&![scopes containsObject:@"chatgpt.tokens.use.direct"])authError=PCError(@"已登录，但没有授权 ChatGPT 套餐用量。请重新开始并确认该权限。");
                    if(token&&claims&&!authError){
                        credentials=@{@"client_id":exchangeID,@"ext_agent_host_id":host,@"access_token":token[@"access_token"],@"refresh_token":token[@"refresh_token"],@"id_token":token[@"id_token"],@"expires_at":@(NSDate.date.timeIntervalSince1970+[token[@"expires_in"] doubleValue]),@"scope":[scopes.allObjects componentsJoinedByString:@" "],@"sub":claims[@"sub"]?:@"",@"email":claims[@"email"]?:@""};
                        @synchronized(attemptLock){if(cancelled){credentials=nil;authError=PCError(@"登录已取消，未保存新凭据。");}else if(!PCSetChatGPTCredentials(credentials,&authError))credentials=nil;}
                    }
                }
            }
            PCOAuthTrace(credentials?@"credentials_saved":@"login_not_completed");finish(credentials, authError);
        });
        if (!authorize) { shutdown(listener, SHUT_RDWR); finish(nil, PCError(@"无法生成 ChatGPT 授权地址。")); return; }
        PCChatGPTBrowserController *authController = [[PCChatGPTBrowserController alloc] initWithURL:authorize callbackURL:[NSURL URLWithString:redirect] cancelHandler:^{
            PCOAuthTrace(@"cancelled_by_user");
            @synchronized(attemptLock){cancelled=YES;}
            shutdown(listener, SHUT_RDWR);
            finish(nil, PCError(@"已取消 ChatGPT 登录。"));
        }];
        authController.localCallback=^(NSURL *url){dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{NSError *failure=nil;if(!PCOAuthDeliverCallbackURL(url,[NSURL URLWithString:redirect],state,&failure)){shutdown(listener,SHUT_RDWR);finish(nil,failure);}});};
        authController.newRegistrationHandler=^{
            PCOAuthTrace(@"switch_registration_requested");
            @synchronized(attemptLock){cancelled=YES;restartRegistration=YES;}
            shutdown(listener,SHUT_RDWR);finish(nil,nil);
        };
        UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:authController];
        weakNavigation = navigation;
        navigation.modalPresentationStyle = UIModalPresentationFullScreen;
        UIViewController *presenter = PCChatGPTPresentationController();
        if (!presenter || presenter.isBeingPresented || presenter.isBeingDismissed) {
            shutdown(listener, SHUT_RDWR); finish(nil, PCError(@"无法打开 iPhone 内的 ChatGPT 登录页面。")); return;
        }
        [presenter presentViewController:navigation animated:YES completion:nil];
    });
}
void PCChatGPTSignIn(void (^completion)(NSDictionary *, NSError *)) {PCChatGPTStartSignIn(NO,completion);}
void PCChatGPTSignInNewAccount(void (^completion)(NSDictionary *, NSError *)) {PCChatGPTStartSignIn(YES,completion);}

BOOL PCRefreshChatGPTCredentials(NSError **error) {
    NSDictionary *old = PCChatGPTCredentials();
    if (![old[@"refresh_token"] isKindOfClass:NSString.class] || ![old[@"refresh_token"] length]) { if (error) *error = PCError(@"ChatGPT 登录已过期，请重新登录。"); return NO; }
    if ([old[@"expires_at"] respondsToSelector:@selector(doubleValue)] && [old[@"expires_at"] doubleValue] > NSDate.date.timeIntervalSince1970 + 180) return YES;
    NSDictionary *form = @{@"grant_type":@"refresh_token", @"client_id":old[@"client_id"] ?: @"", @"refresh_token":old[@"refresh_token"], @"resource":@"https://api.openai.com/v1"};
    NSMutableArray *pairs = [NSMutableArray new]; for (NSString *k in form) [pairs addObject:[NSString stringWithFormat:@"%@=%@", PCFormEscape(k), PCFormEscape(form[k])]];
    NSError *refreshError = nil;
    NSDictionary *token = PCSyncJSON(@"https://auth.openai.com/api/accounts/oauth/token", @"POST", @"application/x-www-form-urlencoded", [[pairs componentsJoinedByString:@"&"] dataUsingEncoding:NSUTF8StringEncoding], &refreshError);
    if (!token) {
        if (error) *error = PCError([NSString stringWithFormat:@"ChatGPT 会话刷新失败：%@", refreshError.localizedDescription ?: @"登录服务未返回凭据"]);
        return NO;
    }
    NSMutableDictionary *fresh = [old mutableCopy];
    fresh[@"access_token"] = token[@"access_token"] ?: @"";
    if ([token[@"refresh_token"] isKindOfClass:NSString.class]) fresh[@"refresh_token"] = token[@"refresh_token"];
    if ([token[@"id_token"] isKindOfClass:NSString.class]) fresh[@"id_token"] = token[@"id_token"];
    fresh[@"expires_at"] = @(NSDate.date.timeIntervalSince1970 + [token[@"expires_in"] doubleValue]);
    return PCSetChatGPTCredentials(fresh, error);
}

void PCChatGPTSignOut(void (^completion)(NSString *)) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSDictionary *credentials = PCChatGPTCredentials();
        NSDictionary *oidc = PCSyncJSON(@"https://auth.openai.com/.well-known/openid-configuration", @"GET", nil, nil, nil);
        NSString *endpoint = oidc[@"revocation_endpoint"];
        NSString *status = @"已从本机移除 ChatGPT 凭据。";
        NSURL *revokeURL = [NSURL URLWithString:endpoint];
        if ([endpoint isKindOfClass:NSString.class] && [revokeURL.scheme.lowercaseString isEqual:@"https"] && [revokeURL.host.lowercaseString isEqual:@"auth.openai.com"] && [credentials[@"refresh_token"] isKindOfClass:NSString.class]) {
            NSDictionary *form = @{@"token":credentials[@"refresh_token"], @"token_type_hint":@"refresh_token", @"client_id":credentials[@"client_id"] ?: @""};
            NSMutableArray *pairs = [NSMutableArray new]; for (NSString *k in form) [pairs addObject:[NSString stringWithFormat:@"%@=%@", PCFormEscape(k), PCFormEscape(form[k])]];
            NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:endpoint]]; req.HTTPMethod = @"POST"; req.HTTPBody = [[pairs componentsJoinedByString:@"&"] dataUsingEncoding:NSUTF8StringEncoding]; [req setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
            dispatch_semaphore_t sem = dispatch_semaphore_create(0); __block NSHTTPURLResponse *response;
            NSURLSession *session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.ephemeralSessionConfiguration delegate:[PCNoRedirect new] delegateQueue:nil];
            [[session dataTaskWithRequest:req completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) { response = (NSHTTPURLResponse *)r; dispatch_semaphore_signal(sem); }] resume]; dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER); [session finishTasksAndInvalidate];
            if (response.statusCode == 200) status = @"已从本机移除，并向 OpenAI 确认撤销登录会话。";
            else status = @"本机凭据已删除；OpenAI 未确认远端撤销。可在 ChatGPT 设置中断开 AsterHand。";
        }
        NSError *clearError; if (!PCSetChatGPTCredentials(nil, &clearError)) status = clearError.localizedDescription;
        dispatch_async(dispatch_get_main_queue(), ^{ completion(status); });
    });
}
