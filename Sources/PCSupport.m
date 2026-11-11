#import "PCLocalization.h"
#import "PCSupport.h"
#import <Security/Security.h>

NSString *PCWorkspace(void) {
    NSString *path = [[NSUserDefaults standardUserDefaults] stringForKey:@"workspace"];
    return path.length ? path : @"/var/mobile/Documents/PocketCodex";
}

NSString *PCSelectedAssistantName(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSString *provider = [defaults stringForKey:@"provider"] ?: @"openai";
    NSString *model = [defaults stringForKey:[@"model." stringByAppendingString:provider]];
    if (!model.length && [provider isEqual:@"openai"]) model = [defaults stringForKey:@"model"];
    if (!model.length) return @"AsterHand";
    NSString *effort = [defaults stringForKey:[@"reasoningEffort." stringByAppendingString:provider]] ?: @"medium";
    if ([provider isEqual:@"openai"] || [provider isEqual:@"chatgpt"]) {
        NSDictionary *names = @{@"":@"自动", @"low":@"低", @"medium":@"中", @"high":@"高", @"xhigh":@"超高", @"max":@"最大"};
        return [NSString stringWithFormat:@"%@ · %@", model, PCLocalized(names[effort] ?: effort)];
    }
    return model;
}

static NSDictionary *secretQuery(NSString *account) {
    return @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
             (__bridge id)kSecAttrService: @"local.pocketcodex.api",
             (__bridge id)kSecAttrAccount: account};
}

static NSData *secretData(NSString *account) {
    NSMutableDictionary *q = [secretQuery(account) mutableCopy];
    q[(__bridge id)kSecReturnData] = @YES;
    q[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef result = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)q, &result) != errSecSuccess) return nil;
    return CFBridgingRelease(result);
}

static BOOL setSecretData(NSString *account, NSData *data, NSError **error) {
    NSDictionary *query = secretQuery(account);
    OSStatus status;
    if (!data.length) {
        status = SecItemDelete((__bridge CFDictionaryRef)query);
        if (status == errSecItemNotFound) status = errSecSuccess;
    } else {
        NSDictionary *values = @{(__bridge id)kSecValueData: data,
            (__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly};
        status = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)values);
        if (status == errSecItemNotFound) {
            NSMutableDictionary *q = [query mutableCopy];
            [q addEntriesFromDictionary:values];
            status = SecItemAdd((__bridge CFDictionaryRef)q, NULL);
        }
    }
    if (status != errSecSuccess && error) *error = PCError([NSString stringWithFormat:@"Keychain 错误 %d；请检查签名与权限。", (int)status]);
    return status == errSecSuccess;
}

NSString *PCAPIKeyForProvider(NSString *provider) {
    NSData *data = secretData(provider ?: @"openai");
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}
NSString *PCAPIKey(void) { return PCAPIKeyForProvider(@"openai"); }
BOOL PCSetAPIKeyForProvider(NSString *provider, NSString *key, NSError **error) {
    return setSecretData(provider ?: @"openai", [key dataUsingEncoding:NSUTF8StringEncoding], error);
}
BOOL PCSetAPIKey(NSString *key, NSError **error) { return PCSetAPIKeyForProvider(@"openai", key, error); }
NSDictionary *PCChatGPTCredentials(void) {
    NSData *data = secretData(@"chatgpt-oauth");
    id value = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}
BOOL PCSetChatGPTCredentials(NSDictionary *credentials, NSError **error) {
    NSData *data = credentials ? [NSJSONSerialization dataWithJSONObject:credentials options:0 error:error] : nil;
    if (credentials && !data) return NO;
    return setSecretData(@"chatgpt-oauth", data, error);
}

NSString *PCJSON(id object) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingPrettyPrinted error:nil];
    return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"{}";
}

NSString *PCRedact(NSString *text) {
    NSString *safe = text ?: @"";
    for (NSString *provider in @[@"openai", @"deepseek", @"anthropic"]) {
        NSString *key = PCAPIKeyForProvider(provider);
        if (key.length) safe = [safe stringByReplacingOccurrencesOfString:key withString:@"[API KEY REDACTED]"];
    }
    NSDictionary *oauth = PCChatGPTCredentials();
    for (NSString *field in @[@"access_token", @"refresh_token", @"id_token"]) {
        NSString *secret = oauth[field];
        if ([secret isKindOfClass:NSString.class] && secret.length) safe = [safe stringByReplacingOccurrencesOfString:secret withString:@"[CHATGPT TOKEN REDACTED]"];
    }
    return safe;
}

NSError *PCError(NSString *message) {
    return [NSError errorWithDomain:@"PocketCodex" code:1 userInfo:@{NSLocalizedDescriptionKey: PCLocalized(message ?: @"未知错误")}];
}
