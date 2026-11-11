#import "PCLocalization.h"

NSString * const PCLanguageDidChangeNotification = @"PCLanguageDidChangeNotification";
static NSString *processLanguage;
NSArray<NSString *> *PCUILanguages(void) { return @[@"system", @"zh-CN", @"en", @"ja", @"es", @"fr"]; }
static NSString *PCResolveLanguage(NSArray<NSString *> *languages) {
    for (NSString *language in languages) {
        NSString *base = [[[language stringByReplacingOccurrencesOfString:@"_" withString:@"-"] lowercaseString] componentsSeparatedByString:@"-"].firstObject;
        if ([base isEqual:@"zh"]) return @"zh-CN";
        if ([@[@"en", @"ja", @"es", @"fr"] containsObject:base]) return base;
    }
    return @"en";
}
NSString *PCUILanguagePreference(void) {
    NSString *value = [NSUserDefaults.standardUserDefaults stringForKey:@"uiLanguage"];
    return [PCUILanguages() containsObject:value] ? value : @"system";
}
NSString *PCResolvedUILanguage(void) {
    if (processLanguage) return processLanguage;
    NSString *preference = PCUILanguagePreference();
    return [preference isEqual:@"system"] ? PCResolveLanguage(NSLocale.preferredLanguages) : preference;
}
NSString *PCUILanguageName(NSString *language) {
    return @{@"system":PCLocalized(@"跟随系统"), @"zh-CN":@"简体中文", @"en":@"English", @"ja":@"日本語", @"es":@"Español", @"fr":@"Français"}[language] ?: @"English";
}
BOOL PCSetUILanguage(NSString *language) {
    if (![PCUILanguages() containsObject:language]) return NO;
    [NSUserDefaults.standardUserDefaults setObject:language forKey:@"uiLanguage"];
    [NSNotificationCenter.defaultCenter postNotificationName:PCLanguageDidChangeNotification object:nil];
    return YES;
}
void PCSetProcessUILanguage(NSString *language) {
    processLanguage = [PCUILanguages() containsObject:language] && ![language isEqual:@"system"] ? [language copy] : nil;
}
NSString *PCLocalized(NSString *source) {
    if (!source.length) return source;
    NSString *language = PCResolvedUILanguage();
    if ([language isEqual:@"zh-CN"]) return source;
    static NSDictionary *catalog; static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *path = [NSBundle.mainBundle pathForResource:@"localizations" ofType:@"json"];
        if (!path) path = [NSProcessInfo.processInfo.arguments.firstObject.stringByDeletingLastPathComponent stringByAppendingPathComponent:@"localizations.json"];
        NSData *data = [NSData dataWithContentsOfFile:path];
        NSDictionary *document = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        catalog = [document[@"messages"] isKindOfClass:NSDictionary.class] ? document[@"messages"] : @{};
    });
    NSDictionary *translations = catalog[source];
    NSString *value=translations[language] ?: translations[@"en"];
    if(value)return value;
    // Match app-owned formatted status copy while preserving captured IDs and values.
    static NSArray *patterns;static NSRegularExpression *token;static dispatch_once_t patternsOnce;
    dispatch_once(&patternsOnce, ^{
        token=[NSRegularExpression regularExpressionWithPattern:@"%(?:[0-9]+\\$)?[-+0 #]*(?:[0-9]+)?(?:\\.[0-9]+)?(?:ll|l)?[@diuf]|\\{[a-zA-Z0-9_]+\\}" options:0 error:nil];
        NSMutableArray *items=[NSMutableArray new];
        for(NSString *key in catalog){NSArray *matches=[token matchesInString:key options:0 range:NSMakeRange(0,key.length)];if(!matches.count||key.length>2048)continue;
            NSMutableString *pattern=[NSMutableString stringWithString:@"^"];NSUInteger offset=0;
            for(NSTextCheckingResult *match in matches){[pattern appendString:[NSRegularExpression escapedPatternForString:[key substringWithRange:NSMakeRange(offset,match.range.location-offset)]]];[pattern appendString:@"([\\s\\S]+?)"];offset=NSMaxRange(match.range);}
            [pattern appendString:[NSRegularExpression escapedPatternForString:[key substringFromIndex:offset]]];[pattern appendString:@"$"];
            NSRegularExpression *regex=[NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];if(regex)[items addObject:@{@"regex":regex,@"key":key}];
        }patterns=items;
    });
    if(source.length<=8192)for(NSDictionary *pattern in patterns){NSTextCheckingResult *match=[pattern[@"regex"] firstMatchInString:source options:0 range:NSMakeRange(0,source.length)];if(!match)continue;
        NSDictionary *entry=catalog[pattern[@"key"]];NSString *format=entry[language]?:entry[@"en"];NSMutableString *result=[format mutableCopy];NSArray *slots=[token matchesInString:format options:0 range:NSMakeRange(0,format.length)];
        if(slots.count+1!=match.numberOfRanges)continue;
        for(NSInteger index=(NSInteger)slots.count-1;index>=0;index--)[result replaceCharactersInRange:[slots[index] range] withString:[source substringWithRange:[match rangeAtIndex:index+1]]];return result;
    }
    for(NSString *prefix in @[@"正在连接 ",@"正在操作 · ",@"命令退出 ",@"保存项目失败：",@"导出失败：",@"保存对话失败：",@"未知屏幕工具：",@"未知文件工具：",@"系统输入执行失败：",@"模型响应未完成：",@"模型列表 HTTP ",@"正在"])
        if([source hasPrefix:prefix]&&source.length>prefix.length)return [PCLocalized(prefix) stringByAppendingString:[source substringFromIndex:prefix.length]];
    for(NSString *suffix in @[@" · 已返回结果",@" 秒无回应已结束语音",@"，正在重试",@" 希望连接这台设备"])
        if([source hasSuffix:suffix]&&source.length>suffix.length)return [[source substringToIndex:source.length-suffix.length] stringByAppendingString:PCLocalized(suffix)];
    NSRange separator=[source rangeOfString:@"："];if(separator.location!=NSNotFound&&separator.location>0){NSString *detail=[source substringFromIndex:NSMaxRange(separator)];if(catalog[detail])return [NSString stringWithFormat:@"%@: %@",[source substringToIndex:separator.location],PCLocalized(detail)];}
    return source;
}
