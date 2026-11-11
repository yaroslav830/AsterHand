#import "PCAPI.h"
#import "PCSupport.h"
#import "PCChatGPTAuth.h"

@interface PCAPI ()
@property(atomic, strong) NSURLSessionDataTask *task;
@property(nonatomic, strong) NSMutableData *streamData;
@property(nonatomic, strong) NSMutableData *streamPending;
@property(nonatomic, strong) NSMutableArray<NSString *> *streamLines;
@property(nonatomic, strong) NSHTTPURLResponse *streamResponse;
@property(nonatomic, strong) NSError *streamFailure;
@property(nonatomic, copy) NSString *lastProgress;
@property(nonatomic, strong) NSMutableString *visibleStreamText;
@property(nonatomic) NSTimeInterval lastTextUpdate;
@end

@implementation PCAPI
{
    dispatch_semaphore_t _streamDone;
}
- (void)cancel { self.cancelled = YES; [self.task cancel]; }

- (void)reportProgress:(NSString *)state {
    if (!state.length || [self.lastProgress isEqual:state]) return;
    self.lastProgress = state;
    if (self.progress) self.progress(state);
}

- (void)consumeProgressEvent {
    if (!self.streamLines.count) return;
    NSMutableArray *parts = [NSMutableArray new];
    for (NSString *line in self.streamLines) if ([line hasPrefix:@"data:"]) {
        NSString *value = [line substringFromIndex:5];
        [parts addObject:[value hasPrefix:@" "] ? [value substringFromIndex:1] : value];
    }
    [self.streamLines removeAllObjects];
    NSDictionary *event = [NSJSONSerialization JSONObjectWithData:[[parts componentsJoinedByString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    if (![event isKindOfClass:NSDictionary.class]) return;
    NSString *type = event[@"type"];
    if ([type isEqual:@"response.output_item.added"]) {
        NSDictionary *item = [event[@"item"] isKindOfClass:NSDictionary.class] ? event[@"item"] : @{};
        NSString *kind = item[@"type"];
        if ([kind isEqual:@"reasoning"]) [self reportProgress:@"思考中…"];
        else if ([kind isEqual:@"function_call"]) [self reportProgress:@"正在准备本机操作…"];
        else if ([kind isEqual:@"message"]) [self reportProgress:@"正在生成回复…"];
    } else if ([type hasPrefix:@"response.reasoning_summary_"]) [self reportProgress:@"思考中 · 正在整理推理摘要…"];
    else if ([type isEqual:@"response.function_call_arguments.delta"]) [self reportProgress:@"正在准备本机操作…"];
    else if ([type isEqual:@"response.output_text.delta"]) {
        [self reportProgress:@"正在生成回复…"];
        if([event[@"delta"] isKindOfClass:NSString.class]){if(!self.visibleStreamText)self.visibleStreamText=[NSMutableString new];if(self.visibleStreamText.length<65536)[self.visibleStreamText appendString:event[@"delta"]];NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;if(now-self.lastTextUpdate>=0.15&&self.liveText){self.lastTextUpdate=now;self.liveText([self.visibleStreamText copy]);}}
    }
    else if ([type isEqual:@"response.completed"]) [self reportProgress:@"响应完成 · 正在整理结果…"];
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    self.streamResponse = (NSHTTPURLResponse *)response;
    [self reportProgress:@"已连接服务端 · 等待模型…"];
    completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    if (self.streamData.length + data.length > 8 * 1024 * 1024) {
        self.streamFailure = PCError(@"API 响应超过 8 MiB，已拒绝处理。");
        [task cancel]; return;
    }
    [self.streamData appendData:data];
    [self.streamPending appendData:data];
    const unsigned char *bytes = self.streamPending.bytes;
    NSUInteger consumed = 0;
    for (NSUInteger i = 0; i < self.streamPending.length; i++) {
        if (bytes[i] != '\n') continue;
        NSUInteger end = i;
        if (end > consumed && bytes[end - 1] == '\r') end--;
        NSString *line = [[NSString alloc] initWithBytes:bytes + consumed length:end - consumed encoding:NSUTF8StringEncoding];
        if (line) {
            if (line.length) [self.streamLines addObject:line];
            else [self consumeProgressEvent];
        }
        consumed = i + 1;
    }
    if (consumed) [self.streamPending replaceBytesInRange:NSMakeRange(0, consumed) withBytes:NULL length:0];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (!self.streamFailure) self.streamFailure = error;
    if (_streamDone) dispatch_semaphore_signal(_streamDone);
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLRequest *))completionHandler {
    completionHandler(nil); // Never forward credentials to another URL.
}

- (NSString *)selectedProvider { return self.provider ?: ([[NSUserDefaults standardUserDefaults] stringForKey:@"provider"] ?: @"openai"); }

// Translate the shared Responses-shaped history into the widely supported
// Chat Completions protocol for custom OpenAI-compatible endpoints.
- (id)compatibleContent:(id)content error:(NSError **)error {
    if([content isKindOfClass:NSString.class])return content;
    if(![content isKindOfClass:NSArray.class])return @"";
    NSMutableArray *parts=[NSMutableArray new];
    for(NSDictionary *part in content){if(![part isKindOfClass:NSDictionary.class])continue;NSString *kind=part[@"type"];
        if([@[@"input_text",@"output_text",@"text"] containsObject:kind]&&[part[@"text"] isKindOfClass:NSString.class])[parts addObject:@{@"type":@"text",@"text":part[@"text"]}];
        else if([kind isEqual:@"input_image"]&&[part[@"image_url"] isKindOfClass:NSString.class])[parts addObject:@{@"type":@"image_url",@"image_url":@{@"url":part[@"image_url"]}}];
        else if([kind isEqual:@"input_file"]){NSString *url=part[@"file_data"];NSRange comma=[url isKindOfClass:NSString.class]?[url rangeOfString:@","]:NSMakeRange(NSNotFound,0);NSData *data=comma.location==NSNotFound?nil:[[NSData alloc] initWithBase64EncodedString:[url substringFromIndex:comma.location+1] options:0];NSString *text=data?[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]:nil;if(!text||[text rangeOfString:[NSString stringWithFormat:@"%C",(unichar)0]].location!=NSNotFound){if(error)*error=PCError(@"通用 API 仅支持图片或 UTF-8 文本附件；此文件无法直接发送。");return nil;}[parts addObject:@{@"type":@"text",@"text":text}];}
    }return parts;
}
- (NSDictionary *)compatibleRequest:(NSDictionary *)body error:(NSError **)error {
    NSMutableArray *messages=[NSMutableArray new],*tools=[NSMutableArray new];
    if([body[@"instructions"] isKindOfClass:NSString.class]&&[body[@"instructions"] length])[messages addObject:@{@"role":@"system",@"content":body[@"instructions"]}];
    for(NSDictionary *item in body[@"input"]){if(![item isKindOfClass:NSDictionary.class])continue;NSString *type=item[@"type"],*role=item[@"role"];
        if([type isEqual:@"function_call_output"]){id content=[self compatibleContent:item[@"output"]?:@"" error:error];if(!content)return nil;[messages addObject:@{@"role":@"tool",@"tool_call_id":item[@"call_id"]?:@"",@"content":content}];}
        else if([type isEqual:@"function_call"]){NSMutableDictionary *message=nil;if(messages.count&&[messages.lastObject[@"role"] isEqual:@"assistant"]&&messages.lastObject[@"tool_calls"])message=[messages.lastObject mutableCopy];else{message=[@{@"role":@"assistant",@"content":NSNull.null,@"tool_calls":@[]} mutableCopy];[messages addObject:message];}NSMutableArray *calls=[message[@"tool_calls"] mutableCopy];[calls addObject:@{@"id":item[@"call_id"]?:@"",@"type":@"function",@"function":@{@"name":item[@"name"]?:@"",@"arguments":item[@"arguments"]?:@"{}"}}];message[@"tool_calls"]=calls;messages[messages.count-1]=message;}
        else if([@[@"user",@"assistant",@"system"] containsObject:role?:@""]){id content=[self compatibleContent:item[@"content"]?:@"" error:error];if(!content)return nil;[messages addObject:@{@"role":role,@"content":content}];}
    }
    for(NSDictionary *tool in body[@"tools"])if([tool[@"type"] isEqual:@"function"])[tools addObject:@{@"type":@"function",@"function":@{@"name":tool[@"name"]?:@"",@"description":tool[@"description"]?:@"",@"parameters":tool[@"parameters"]?:@{}}}];
    NSMutableDictionary *wire=[@{@"model":body[@"model"]?:@"",@"messages":messages,@"max_tokens":body[@"max_output_tokens"]?:@8192,@"stream":@NO} mutableCopy];if(tools.count)wire[@"tools"]=tools;return wire;
}
- (NSDictionary *)normalizeCompatible:(NSDictionary *)response error:(NSError **)error {
    NSDictionary *choice=[response[@"choices"] isKindOfClass:NSArray.class]?[response[@"choices"] firstObject]:nil,*message=[choice[@"message"] isKindOfClass:NSDictionary.class]?choice[@"message"]:nil;NSString *finish=choice[@"finish_reason"];
    if(!message||![finish isKindOfClass:NSString.class]||![@[@"stop",@"tool_calls"] containsObject:finish]){if(error)*error=PCError(@"通用 API 返回了不完整或无法识别的响应。");return nil;}
    NSMutableArray *output=[NSMutableArray new];if([message[@"content"] isKindOfClass:NSString.class]&&[message[@"content"] length])[output addObject:@{@"type":@"message",@"role":@"assistant",@"content":@[@{@"type":@"output_text",@"text":message[@"content"]}]}];
    for(NSDictionary *call in message[@"tool_calls"]){NSDictionary *fn=[call[@"function"] isKindOfClass:NSDictionary.class]?call[@"function"]:nil;if(fn)[output addObject:@{@"type":@"function_call",@"call_id":call[@"id"]?:@"",@"name":fn[@"name"]?:@"",@"arguments":fn[@"arguments"]?:@"{}"}];}
    NSDictionary *usage=[response[@"usage"] isKindOfClass:NSDictionary.class]?response[@"usage"]:@{};return @{@"status":@"completed",@"output":output,@"usage":@{@"input_tokens":usage[@"prompt_tokens"]?:@0,@"output_tokens":usage[@"completion_tokens"]?:@0}};
}

- (NSArray *)anthropicMessages:(NSArray *)history {
    NSMutableArray *messages = [NSMutableArray new];
    for (NSDictionary *item in history) {
        NSString *role = nil; id content = nil;
        if ([item[@"role"] isEqual:@"user"]) { role = @"user"; content = item[@"content"] ?: @""; }
        else if ([item[@"type"] isEqual:@"message"]) {
            role = @"assistant"; NSMutableArray *parts = [NSMutableArray new];
            for (NSDictionary *part in item[@"content"]) {
                NSString *text = part[@"text"] ?: part[@"refusal"];
                if ([text isKindOfClass:NSString.class] && text.length) [parts addObject:@{@"type": @"text", @"text": text}];
            }
            if (parts.count) content = parts;
        } else if ([item[@"type"] isEqual:@"function_call"]) {
            role = @"assistant"; id input = [NSJSONSerialization JSONObjectWithData:[(item[@"arguments"] ?: @"{}") dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
            content = @[@{@"type": @"tool_use", @"id": item[@"call_id"] ?: @"", @"name": item[@"name"] ?: @"", @"input": [input isKindOfClass:NSDictionary.class] ? input : @{}}];
        } else if ([item[@"type"] isEqual:@"function_call_output"]) {
            role = @"user"; content = @[@{@"type": @"tool_result", @"tool_use_id": item[@"call_id"] ?: @"", @"content": item[@"output"] ?: @""}];
        }
        if (!role || !content) continue;
        if (messages.count && [messages.lastObject[@"role"] isEqual:role]) {
            NSMutableDictionary *last = [messages.lastObject mutableCopy];
            id previous = last[@"content"];
            NSMutableArray *merged = [NSMutableArray new];
            if ([previous isKindOfClass:NSArray.class]) [merged addObjectsFromArray:previous];
            else if ([previous isKindOfClass:NSString.class] && [previous length]) [merged addObject:@{@"type": @"text", @"text": previous}];
            if ([content isKindOfClass:NSArray.class]) [merged addObjectsFromArray:content];
            else [merged addObject:@{@"type": @"text", @"text": content}];
            last[@"content"] = merged; messages[messages.count - 1] = last;
        } else [messages addObject:@{@"role": role, @"content": content}];
    }
    return messages;
}

- (NSDictionary *)anthropicRequest:(NSDictionary *)body {
    NSArray *history = [body[@"input"] isKindOfClass:NSArray.class] ? body[@"input"] : @[];
    NSMutableArray *tools = [NSMutableArray new];
    for (NSDictionary *tool in body[@"tools"]) {
        if (![tool[@"type"] isEqual:@"function"]) continue;
        [tools addObject:@{@"name": tool[@"name"] ?: @"", @"description": tool[@"description"] ?: @"", @"input_schema": tool[@"parameters"] ?: @{@"type": @"object", @"properties": @{}, @"additionalProperties": @NO}}];
    }
    NSMutableDictionary *request = [@{@"model": body[@"model"] ?: @"", @"messages": [self anthropicMessages:history], @"max_tokens": body[@"max_output_tokens"] ?: @8192} mutableCopy];
    if ([body[@"instructions"] isKindOfClass:NSString.class]) request[@"system"] = body[@"instructions"];
    if (tools.count) request[@"tools"] = tools;
    return request;
}

- (NSDictionary *)normalizeAnthropic:(NSDictionary *)response {
    NSMutableArray *output = [NSMutableArray new], *textParts = [NSMutableArray new];
    for (NSDictionary *block in response[@"content"]) {
        if ([block[@"type"] isEqual:@"text"] && [block[@"text"] isKindOfClass:NSString.class]) {
            [textParts addObject:@{@"type": @"output_text", @"text": block[@"text"]}];
        } else if ([block[@"type"] isEqual:@"tool_use"]) {
            NSString *arguments = PCJSON(block[@"input"] ?: @{});
            [output addObject:@{@"type": @"function_call", @"call_id": block[@"id"] ?: @"", @"name": block[@"name"] ?: @"", @"arguments": arguments}];
        }
    }
    if (textParts.count) [output insertObject:@{@"type": @"message", @"role": @"assistant", @"content": textParts} atIndex:0];
    return @{@"status": @"completed", @"output": output,
             @"usage": @{@"input_tokens": response[@"usage"][@"input_tokens"] ?: @0, @"output_tokens": response[@"usage"][@"output_tokens"] ?: @0}};
}

static NSString *PCStreamFailure(id value) {
    NSDictionary *errorObject = [value isKindOfClass:NSDictionary.class] ? value : nil;
    NSDictionary *nested = [errorObject[@"error"] isKindOfClass:NSDictionary.class] ? errorObject[@"error"] : nil;
    if (nested) errorObject = nested;
    NSString *message = [errorObject[@"message"] isKindOfClass:NSString.class] ? errorObject[@"message"] : nil;
    NSString *code = [errorObject[@"code"] isKindOfClass:NSString.class] ? errorObject[@"code"] : nil;
    if ([code isEqual:@"subscription_sharing_usage_limit_exceeded"] || [code isEqual:@"subscription_sharing_usage_unavailable"]) {
        return message.length ? [NSString stringWithFormat:@"ChatGPT 套餐用量请求受限（%@）：%@", code, message] : [NSString stringWithFormat:@"ChatGPT 套餐用量请求受限（%@）。", code];
    }
    if (!message.length && code.length) message = code;
    return PCRedact(message ?: @"");
}

NSDictionary *PCParseCompletedSSE(NSData *data, NSError **error) {
    NSString *source = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
    NSMutableArray<NSString *> *dataLines = [NSMutableArray new];
    __block NSDictionary *completed = nil;
    __block NSDictionary *incomplete = nil;
    __block NSString *failure = nil;
    __block NSMutableString *textDelta = [NSMutableString new];
    __block NSMutableDictionary<NSNumber *, NSDictionary *> *doneItems = [NSMutableDictionary new];
    void (^consume)(void) = ^{
        if (!dataLines.count) return;
        NSString *payload = [dataLines componentsJoinedByString:@"\n"];
        [dataLines removeAllObjects];
        if ([payload isEqual:@"[DONE]"]) return;
        NSDictionary *event = [NSJSONSerialization JSONObjectWithData:[payload dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        if (![event isKindOfClass:NSDictionary.class]) return;
        NSString *type = [event[@"type"] isKindOfClass:NSString.class] ? event[@"type"] : @"";
        if ([type isEqual:@"response.output_text.delta"] && [event[@"delta"] isKindOfClass:NSString.class]) [textDelta appendString:event[@"delta"]];
        else if ([type isEqual:@"response.output_item.done"] && [event[@"item"] isKindOfClass:NSDictionary.class]
                 && [event[@"output_index"] isKindOfClass:NSNumber.class]) doneItems[event[@"output_index"]] = event[@"item"];
        else if ([type isEqual:@"response.completed"] && [event[@"response"] isKindOfClass:NSDictionary.class]) completed = event[@"response"];
        else if ([type isEqual:@"response.incomplete"] && [event[@"response"] isKindOfClass:NSDictionary.class]) incomplete = event[@"response"];
        else if ([type isEqual:@"response.failed"] || [type isEqual:@"error"]) failure = PCStreamFailure(event[@"response"] ?: event[@"error"] ?: event);
    };
    for (NSString *line in [source componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        if (!line.length) { consume(); continue; }
        if (![line hasPrefix:@"data:"]) continue;
        NSString *value = [line substringFromIndex:5];
        if ([value hasPrefix:@" "]) value = [value substringFromIndex:1];
        [dataLines addObject:value];
    }
    consume();
    if (completed && !failure.length) {
        NSMutableDictionary *result = [completed mutableCopy];
        NSArray *output = [result[@"output"] isKindOfClass:NSArray.class] ? result[@"output"] : @[];
        if (!output.count && doneItems.count) {
            NSArray *indexes = [[doneItems allKeys] sortedArrayUsingSelector:@selector(compare:)];
            NSMutableArray *reconstructed = [NSMutableArray new];
            for (NSNumber *index in indexes) [reconstructed addObject:doneItems[index]];
            result[@"output"] = reconstructed;
        }
        if (![result[@"output_text"] isKindOfClass:NSString.class] && textDelta.length) result[@"output_text"] = textDelta;
        return result;
    }
    NSString *detail = nil;
    if (incomplete) {
        NSDictionary *details = [incomplete[@"incomplete_details"] isKindOfClass:NSDictionary.class] ? incomplete[@"incomplete_details"] : nil;
        detail = [details[@"reason"] isKindOfClass:NSString.class] ? details[@"reason"] : nil;
    }
    if (error) {
        NSString *message = failure.length ? failure : (detail.length ? [NSString stringWithFormat:@"响应未完成（%@）。", detail] : (textDelta.length ? @"流中已收到文本，但连接在 response.completed 之前结束。" : @"ChatGPT 套餐请求未收到 response.completed 事件。"));
        *error = PCError(PCRedact(message));
    }
    return nil;
}

- (NSDictionary *)request:(NSString *)path body:(NSDictionary *)body error:(NSError **)error {
    if (self.cancelled) { if (error) *error = PCError(@"已停止"); return nil; }
    NSString *provider = [self selectedProvider];
    BOOL chatGPT = [provider isEqual:@"chatgpt"];
    if (chatGPT) {
        NSError *refreshError;
        if (!PCRefreshChatGPTCredentials(&refreshError)) { if (error) *error = refreshError; return nil; }
        NSString *scope = PCChatGPTCredentials()[@"scope"];
        if (![scope containsString:@"chatgpt.tokens.use.direct"]) { if (error) *error = PCError(@"当前 ChatGPT 登录未授权套餐用量，请重新登录并启用该权限。"); return nil; }
    }
    NSString *key = chatGPT ? PCChatGPTCredentials()[@"access_token"] : PCAPIKeyForProvider(provider);
    if (![key isKindOfClass:NSString.class] || !key.length) {
        if (error) *error = PCError(chatGPT ? @"请先在设置中使用 Sign in with ChatGPT 登录并允许套餐用量。" : [NSString stringWithFormat:@"请先在设置中保存 %@ API Key。", provider]); return nil;
    }
    BOOL anthropic = [provider isEqual:@"anthropic"];
    NSString *custom=[provider isEqual:@"openai"]?[[NSUserDefaults.standardUserDefaults stringForKey:@"apiBase.openai"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]:nil;
    BOOL compatible=custom.length&&![[custom.lowercaseString stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]] isEqual:@"https://api.openai.com/v1"];
    NSString *base = [provider isEqual:@"deepseek"] ? @"https://api.deepseek.com/" : (anthropic ? @"https://api.anthropic.com/v1/" : @"https://api.openai.com/v1/");
    if(custom.length){NSURLComponents *parts=[NSURLComponents componentsWithString:custom];if(![parts.scheme.lowercaseString isEqual:@"https"]||!parts.host.length||parts.user.length||parts.password.length||parts.query.length||parts.fragment.length){if(error)*error=PCError(@"API 地址必须是 HTTPS，且不能包含账户、查询参数或片段。");return nil;}base=[custom hasSuffix:@"/"]?custom:[custom stringByAppendingString:@"/"];}
    NSString *route = [path isEqual:@"responses"] && compatible ? @"chat/completions" : ([path isEqual:@"responses"] && anthropic ? @"messages" : ([path isEqual:@"models"] && anthropic ? @"models?limit=100" : path));
    NSURL *url = [NSURL URLWithString:[base stringByAppendingString:route]];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = body ? @"POST" : @"GET"; req.timeoutInterval = 120;
    if (anthropic) {
        [req setValue:key forHTTPHeaderField:@"x-api-key"];
        [req setValue:@"2023-06-01" forHTTPHeaderField:@"anthropic-version"];
    } else [req setValue:[@"Bearer " stringByAppendingString:key] forHTTPHeaderField:@"Authorization"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    BOOL streamed = chatGPT && [path isEqual:@"responses"];
    if (streamed) [req setValue:@"text/event-stream" forHTTPHeaderField:@"Accept"];
    if (body) {
        NSDictionary *wireBody = compatible && [path isEqual:@"responses"] ? [self compatibleRequest:body error:error] : (anthropic && [path isEqual:@"responses"] ? [self anthropicRequest:body] : body);
        if(!wireBody)return nil;
        req.HTTPBody = [NSJSONSerialization dataWithJSONObject:wireBody options:0 error:error];
        if (!req.HTTPBody) return nil;
    }
    NSURLSessionConfiguration *cfg = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    cfg.timeoutIntervalForRequest = 120; cfg.timeoutIntervalForResource = 125;
    cfg.HTTPCookieStorage = nil; cfg.URLCache = nil;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg delegate:self delegateQueue:nil];
    __block NSData *received; __block NSHTTPURLResponse *response; __block NSError *failure;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    if (streamed) {
        self.streamData = [NSMutableData new];
    self.visibleStreamText=[NSMutableString new];self.lastTextUpdate=0; self.streamPending = [NSMutableData new];
        self.streamLines = [NSMutableArray new]; self.streamResponse = nil; self.streamFailure = nil;
        self.lastProgress = nil; _streamDone = done;
        self.task = [session dataTaskWithRequest:req];
    } else self.task = [session dataTaskWithRequest:req completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        received = d; response = (NSHTTPURLResponse *)r; failure = e; dispatch_semaphore_signal(done);
    }];
    [self reportProgress:streamed ? @"正在连接 ChatGPT…" : @"正在连接 AI 服务…"];
    [self.task resume];
    if (self.cancelled) [self.task cancel];
    while (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC))) if (self.cancelled) [self.task cancel];
    if (streamed) { received = self.streamData.copy; response = self.streamResponse; failure = self.streamFailure; _streamDone = nil; }
    [session finishTasksAndInvalidate]; self.task = nil;
    if (self.cancelled) { if (error) *error = PCError(@"已停止"); return nil; }
    if (failure) {
        if (error) *error = PCError(PCRedact([NSString stringWithFormat:@"请求 %@ 失败：%@", url.host ?: @"AI 服务", failure.localizedDescription ?: @"网络错误"]));
        return nil;
    }
    if (received.length > 8 * 1024 * 1024) { if (error) *error = PCError(@"API 响应超过 8 MiB，已拒绝处理。"); return nil; }
    id json = received ? [NSJSONSerialization JSONObjectWithData:received options:0 error:nil] : nil;
    if (streamed && response.statusCode >= 200 && response.statusCode < 300) {
        NSDictionary *completed = PCParseCompletedSSE(received, error);
        if (!completed) return nil;
        json = completed;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
        NSString *message = PCStreamFailure(json);
        if (!message.length) {
            NSString *raw = [[NSString alloc] initWithData:received encoding:NSUTF8StringEncoding] ?: @"";
            if (streamed) {
                NSError *streamError;
                PCParseCompletedSSE(received, &streamError);
                if (streamError.localizedDescription.length) message = streamError.localizedDescription;
            }
            if (!message.length && raw.length && ![raw hasPrefix:@"{"]) message = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        }
        if (!message.length) message = @"请求失败；请检查网络、账户额度和模型权限。";
        if (message.length > 1200) message = [message substringToIndex:1200];
        if (error) *error = PCError(PCRedact([NSString stringWithFormat:@"HTTP %ld：%@", (long)response.statusCode, message])); return nil;
    }
    if (![json isKindOfClass:NSDictionary.class]) { if (error) *error = PCError(@"API 返回非 JSON 对象。"); return nil; }
    return compatible && [path isEqual:@"responses"] ? [self normalizeCompatible:json error:error] : (anthropic && [path isEqual:@"responses"] ? [self normalizeAnthropic:json] : json);
}
@end
