#import "PCSelfTest.h"
#import "PCProcess.h"
#import "PCTools.h"
#import "PCPlatform.h"
#import "PCAPI.h"
#import "PCSupport.h"
#import "PCAttachment.h"
#import "PCProjectStore.h"
#import "PCLocalization.h"
#import "PCAgent.h"
#import "PCMessageQueue.h"
#import "PCQuestion.h"
#import "PCDiscovery.h"
#import "PCRootPermission.h"
#import "PCControl.h"
#import "PCOAuthListener.h"
#import "PCChatGPTAuth.h"
#import <Security/Security.h>
#import <TargetConditionals.h>
#import <time.h>
#import <string.h>
#include <pwd.h>
#include <sys/stat.h>
#include <unistd.h>

@interface PCAPI (PCCompatibleFixture)
- (NSDictionary *)compatibleRequest:(NSDictionary *)body error:(NSError **)error;
- (NSDictionary *)normalizeCompatible:(NSDictionary *)response error:(NSError **)error;
@end

static int cancelAfter(void *context) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec + t.tv_nsec / 1e9 >= *(double *)context;
}

NSDictionary *PCOfflineSelfTest(void) {
    NSMutableDictionary *results = [NSMutableDictionary new];
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *temp = [NSTemporaryDirectory() stringByAppendingPathComponent:[@"PocketCodex-selftest-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    NSError *error;
    if (![fm createDirectoryAtPath:temp withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions: @0700} error:&error]) return @{@"error": error.localizedDescription};
    NSDictionary *previousDomain=[NSUserDefaults.standardUserDefaults volatileDomainForName:NSArgumentDomain];NSMutableDictionary *testDomain=[previousDomain mutableCopy]?:[NSMutableDictionary new];testDomain[@"workspace"]=PCVirtualPath(temp);[NSUserDefaults.standardUserDefaults setVolatileDomain:testDomain forName:NSArgumentDomain];
    @try {
        PCAPI *compatibleAPI=[PCAPI new];NSError *compatibleError=nil;
        NSDictionary *fixture=@{@"model":@"fixture",@"instructions":@"system",@"input":@[@{@"role":@"user",@"content":@[@{@"type":@"input_text",@"text":@"hello"}]},@{@"type":@"function_call",@"call_id":@"c1",@"name":@"test",@"arguments":@"{}"},@{@"type":@"function_call_output",@"call_id":@"c1",@"output":@"ok"}],@"tools":@[@{@"type":@"function",@"name":@"test",@"parameters":@{@"type":@"object"}}]};
        NSDictionary *compatibleWire=[compatibleAPI compatibleRequest:fixture error:&compatibleError];NSArray *messages=compatibleWire[@"messages"];results[@"compatible_api_preserves_tool_roundtrip"]=@(!compatibleError&&messages.count==4&&[messages[2][@"tool_calls"][0][@"id"] isEqual:@"c1"]&&[messages[3][@"tool_call_id"] isEqual:@"c1"]&&[compatibleWire[@"tools"][0][@"function"][@"name"] isEqual:@"test"]);
        NSDictionary *compatibleParsed=[compatibleAPI normalizeCompatible:@{@"choices":@[@{@"finish_reason":@"tool_calls",@"message":@{@"content":NSNull.null,@"tool_calls":@[@{@"id":@"c1",@"function":@{@"name":@"test",@"arguments":@"{}"}}]}}]} error:&compatibleError];results[@"compatible_api_parses_function_calls"]=@([compatibleParsed[@"output"][0][@"call_id"] isEqual:@"c1"]);
        compatibleError=nil;results[@"compatible_api_rejects_incomplete_response"]=@(![compatibleAPI normalizeCompatible:@{@"choices":@[@{@"finish_reason":@"length",@"message":@{}}]} error:&compatibleError]&&compatibleError!=nil);
        [results addEntriesFromDictionary:PCOAuthListenerSelfTest()];
        [results addEntriesFromDictionary:PCChatGPTAuthorizationSelfTest()];
        NSString *controlTest=[temp stringByAppendingPathComponent:@"control-state.json"];NSError *controlError=nil;
        BOOL missingControl=PCControlReadStateFile(controlTest,&controlError)!=nil&&!controlError;
        NSData *damaged=[@"{invalid" dataUsingEncoding:NSUTF8StringEncoding];[damaged writeToFile:controlTest atomically:YES];
        BOOL malformedControl=PCControlReadStateFile(controlTest,&controlError)==nil&&controlError!=nil;
        results[@"control_state_read_failure_preserves_identity_file"]=@(missingControl&&malformedControl&&[[NSData dataWithContentsOfFile:controlTest] isEqual:damaged]);
        NSData *(^discoveryWire)(NSString *)=^NSData *(NSString *s){return [s dataUsingEncoding:NSUTF8StringEncoding];};
        results[@"discovery_content_length_and_chunked"]=@([PCDiscoveryDecodeJSON(discoveryWire(@"HTTP/1.1 200 OK\r\nContent-Length: 11\r\n\r\n{\"ok\":true}"))[@"ok"] boolValue]&&[PCDiscoveryDecodeJSON(discoveryWire(@"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\n{\"ok\"\r\n6\r\n:true}\r\n0\r\n\r\n"))[@"ok"] boolValue]);
        results[@"discovery_rejects_truncated_or_failed_http"]=@(!PCDiscoveryDecodeJSON(discoveryWire(@"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n10000\r\n{}"))&&!PCDiscoveryDecodeJSON(discoveryWire(@"HTTP/1.1 403 Forbidden\r\n\r\n{}"))&&!PCDiscoveryDecodeJSON(discoveryWire(@"HTTP/1.1 200 OK\r\nContent-Length: 99\r\n\r\n{}")));
        NSDictionary *questionState=@{@"id":@"job-a",@"running":@YES,@"context":@{@"chat":@"chat-a"},@"question":@{@"id":@"prompt-a",@"kind":@"question",@"options":@[@"选项一",@"选项二"]}};
        results[@"question_reply_bound_to_job_prompt_chat"]=@(PCQuestionReplyMatches(questionState,@"job-a",@"prompt-a",@"chat-a")&&!PCQuestionReplyMatches(questionState,@"job-b",@"prompt-a",@"chat-a")&&!PCQuestionReplyMatches(questionState,@"job-a",@"prompt-b",@"chat-a")&&!PCQuestionReplyMatches(questionState,@"job-a",@"prompt-a",@"chat-b"));
        NSMutableDictionary *invalidQuestion=[questionState mutableCopy];invalidQuestion[@"question"]=@{@"id":@"prompt-a",@"kind":@"approval"};BOOL approvalRejected=!PCQuestionReplyMatches(invalidQuestion,@"job-a",@"prompt-a",@"chat-a");invalidQuestion[@"question"]=questionState[@"question"];invalidQuestion[@"running"]=@NO;
        results[@"question_reply_rejects_approval_and_finished"]=@(approvalRejected&&!PCQuestionReplyMatches(invalidQuestion,@"job-a",@"prompt-a",@"chat-a"));
        NSMutableDictionary *rootQuestion=[questionState mutableCopy];rootQuestion[@"question"]=@{@"id":@"prompt-a",@"kind":@"root_permission"};
        results[@"root_permission_requires_exact_choice_and_current_prompt"]=@(PCQuestionReplyMatches(rootQuestion,@"job-a",@"prompt-a",@"chat-a")&&!PCQuestionReplyMatches(rootQuestion,@"job-a",@"old",@"chat-a")&&PCRootPermissionAnswerValid(@"允许一次")&&PCRootPermissionAnswerValid(@"始终允许")&&PCRootPermissionAnswerValid(@"不允许")&&!PCRootPermissionAnswerValid(@YES)&&!PCRootPermissionAnswerValid(@"允许"));
        results[@"root_permission_restricts_operation"]=@(PCRootOperationValid(@"run_shell",@{@"command":@"id -u",@"timeout_seconds":@5})&&!PCRootOperationValid(@"remote_execute",@{})&&!PCRootOperationValid(@"run_shell",@{@"command":@"id -u",@"timeout_seconds":@121})&&!PCRootOperationValid(@"read_file",@{@"path":@"x",@"offset":@(-1)}));
        NSMutableDictionary *grants=[NSMutableDictionary new];NSDictionary *grant=@{@"grant":NSUUID.UUID.UUIDString,@"prompt":NSUUID.UUID.UUIDString,@"job":@"job-a",@"created":@1000};
        results[@"root_once_consumed_before_execution"]=@(PCRootOnceClaim(grant,grants,1000)&&!PCRootOnceClaim(grant,grants,1001));
        results[@"root_once_rejects_expiry_and_missing_binding"]=@(!PCRootOnceClaim(grant,[NSMutableDictionary new],1031)&&!PCRootOnceClaim(grant,[NSMutableDictionary new],990)&&!PCRootOnceClaim(@{@"grant":NSUUID.UUID.UUIDString,@"created":@1000},[NSMutableDictionary new],1000));
        NSString *queue=[temp stringByAppendingPathComponent:@"inbox"],*queueError=nil,*job=NSUUID.UUID.UUIDString.lowercaseString;
        NSString *firstMessage=PCMessageEnqueue(queue,@"任务补充一",job,nil,&queueError),*secondMessage=PCMessageEnqueue(queue,@"任务补充二",job,nil,&queueError);
        NSArray *pending=PCMessagePending(queue);results[@"overlay_messages_do_not_overwrite"]=@(firstMessage&&secondMessage&&pending.count==2);
        results[@"overlay_message_validation"]=@(!PCMessageEnqueue(queue,@" ",job,nil,nil)&&!PCMessageEnqueue(queue,@"test",@"../escape",nil,nil)&&!PCMessageEnqueue(queue,@"test",nil,@{},nil));
        NSDictionary *firstItem=pending.firstObject;PCMessageAcknowledge(queue,firstItem,@"accepted",@"queued");
        results[@"overlay_message_receipt_and_isolation"]=@(PCMessagePending(queue).count==1&&[PCMessageReceipt(queue,firstItem[@"id"])[@"status"] isEqual:@"accepted"]&&!PCMessageReceipt(queue,@"../escape"));
        PCTools *tools = [PCTools new];
        tools.workspace = PCVirtualPath(temp);
        if(geteuid()==0){struct passwd *mobile=getpwnam("mobile");if(mobile){NSString *project=[temp stringByAppendingPathComponent:@"mobile-workspace"];[fm createDirectoryAtPath:project withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];chown(project.fileSystemRepresentation,mobile->pw_uid,mobile->pw_gid);PCTools *rootTools=[PCTools new];rootTools.workspace=PCVirtualPath(project);NSDictionary *written=[rootTools execute:@"write_file" arguments:@{@"path":@"source.txt",@"content":@"first"}];NSString *file=[project stringByAppendingPathComponent:@"source.txt"];chown(file.fileSystemRepresentation,0,0);NSDictionary *updated=[rootTools execute:@"write_file" arguments:@{@"path":@"source.txt",@"content":@"second"}];struct stat metadata;results[@"root_project_writes_remain_owned_by_project_user"]=@(!written[@"error"]&&!updated[@"error"]&&stat(file.fileSystemRepresentation,&metadata)==0&&metadata.st_uid==mobile->pw_uid);}}
        NSDictionary *first = [tools execute:@"write_file" arguments:@{@"path": @"test.txt", @"content": @"original 中文"}];
        NSDictionary *second = [tools execute:@"write_file" arguments:@{@"path": @"test.txt", @"content": @"updated"}];
        NSDictionary *read = [tools execute:@"read_file" arguments:@{@"path": @"test.txt", @"offset": @0}];
        NSString *backup = [second[@"backup"] isKindOfClass:NSString.class] ? [NSString stringWithContentsOfFile:PCRealPath(second[@"backup"]) encoding:NSUTF8StringEncoding error:nil] : nil;
        results[@"file_write_read_backup"] = @(!first[@"error"] && !second[@"error"] && [read[@"text"] isEqual:@"updated"] && [backup isEqual:@"original 中文"]);
        NSString *link = [temp stringByAppendingPathComponent:@"link.txt"];
        [fm createSymbolicLinkAtPath:link withDestinationPath:@"test.txt" error:nil];
        results[@"symlink_write_rejected"] = @([tools execute:@"write_file" arguments:@{@"path": @"link.txt", @"content": @"must-not-overwrite"}][@"error"] != nil);
        NSMutableString *utf8 = [NSMutableString stringWithString:@"a"];
        for (NSUInteger i = 0; i < 20000; i++) [utf8 appendString:@"中"];
        [tools execute:@"write_file" arguments:@{@"path": @"utf8.txt", @"content": utf8}];
        NSDictionary *chunk1 = [tools execute:@"read_file" arguments:@{@"path": @"utf8.txt", @"offset": @0}];
        NSDictionary *chunk2 = [tools execute:@"read_file" arguments:@{@"path": @"utf8.txt", @"offset": chunk1[@"next_offset"] ?: @0}];
        NSString *joined = [chunk1[@"text"] stringByAppendingString:chunk2[@"text"] ?: @""];
        results[@"utf8_chunk_boundary"] = @([joined isEqual:utf8]);
        NSDictionary *listing = [tools execute:@"list_directory" arguments:@{@"path": @"."}];
        results[@"directory_listing"] = @([listing[@"entries"] containsObject:@"test.txt"]);
        const char *shell = TARGET_OS_IPHONE ? PCShellPath().fileSystemRepresentation : "/bin/sh";
        NSString *shellCwd = PCVirtualPath(temp);
        PCProcessResult p = PCRunShell(shell, "printf 'local-ok'; exit 7", shellCwd.UTF8String, 2, 512, NULL, NULL);
        results[@"shell_output_and_exit"] = @(!p.spawn_error && p.exit_code == 7 && p.output_length == 8 && !memcmp(p.output, "local-ok", 8));
        PCFreeProcessResult(&p);
        NSDictionary *windowsShell=[tools execute:@"run_shell" arguments:@{@"command":@"printf 'line1'\r\nprintf 'line2'\r\n",@"timeout_seconds":@2}];
        results[@"shell_windows_line_endings"]=@([windowsShell[@"output"] isEqual:@"line1line2"]&&[windowsShell[@"exit_code"] intValue]==0);
        // Leave time for jailbreak exec/trust hooks before testing a noisy child.
        p = PCRunShell(shell, "while :; do printf '0123456789abcdef'; done", shellCwd.UTF8String, 1.0, 512, NULL, NULL);
        results[@"shell_timeout_and_truncation"] = @(!p.spawn_error && p.timed_out && p.truncated && p.output_length == 512);
        if(![results[@"shell_timeout_and_truncation"] boolValue])results[@"shell_timeout_diagnostic"]=@{@"spawn_error":@(p.spawn_error),@"timed_out":@(p.timed_out),@"truncated":@(p.truncated),@"output_bytes":@(p.output_length),@"exit_code":@(p.exit_code)};
        PCFreeProcessResult(&p);
        struct timespec now;
        clock_gettime(CLOCK_MONOTONIC, &now);
        double deadline = now.tv_sec + now.tv_nsec / 1e9 + 0.2;
        p = PCRunShell(shell, "sleep 10", shellCwd.UTF8String, 2, 512, cancelAfter, &deadline);
        results[@"shell_cancellation"] = @(!p.spawn_error && p.cancelled && !p.timed_out);
        PCFreeProcessResult(&p);
        NSMutableDictionary *query = [@{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
            (__bridge id)kSecAttrService: @"local.pocketcodex.selftest",
            (__bridge id)kSecAttrAccount: NSUUID.UUID.UUIDString} mutableCopy];
        NSMutableDictionary *add = [query mutableCopy];
        NSData *probe = [@"offline-probe" dataUsingEncoding:NSUTF8StringEncoding];
        add[(__bridge id)kSecValueData] = probe;
        add[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly;
        OSStatus added = SecItemAdd((__bridge CFDictionaryRef)add, NULL);
        query[(__bridge id)kSecReturnData] = @YES;
        CFTypeRef result = NULL;
        OSStatus found = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
        NSData *returned = CFBridgingRelease(result);
        [query removeObjectForKey:(__bridge id)kSecReturnData];
        OSStatus removed = SecItemDelete((__bridge CFDictionaryRef)query);
        results[@"keychain_roundtrip"] = @(added == errSecSuccess && found == errSecSuccess && removed == errSecSuccess && [probe isEqual:returned]);
        results[@"keychain_status"] = @{@"add": @(added), @"read": @(found), @"delete": @(removed)};
        NSDictionary *item = @{@"type": @"response.output_item.done", @"output_index": @0,
            @"item": @{@"type": @"message", @"role": @"assistant", @"content": @[@{@"type": @"output_text", @"text": @"fixture-ok"}]}};
        NSDictionary *terminal = @{@"type": @"response.completed", @"response": @{@"status": @"completed", @"output": @[]}};
        NSString *itemJSON = [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:item options:0 error:nil] encoding:NSUTF8StringEncoding];
        NSString *terminalJSON = [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:terminal options:0 error:nil] encoding:NSUTF8StringEncoding];
        NSString *sse = [NSString stringWithFormat:@"data: %@\n\ndata: %@\n\n", itemJSON, terminalJSON];
        NSDictionary *parsed = PCParseCompletedSSE([sse dataUsingEncoding:NSUTF8StringEncoding], nil);
        results[@"sse_completed_item_recovery"] = @([parsed[@"output"] count] == 1 && [parsed[@"output"][0][@"content"][0][@"text"] isEqual:@"fixture-ok"]);
        NSString *workspace = PCVirtualPath(temp);
        NSString *sample = [temp stringByAppendingPathComponent:@"sample.txt"];
        [@"attachment fixture" writeToFile:sample atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSDictionary *attachment = PCAttachmentImport([NSURL fileURLWithPath:sample], workspace, &error);
        NSArray *attachmentHistory = @[@{@"role":@"user", @"content":@"read this", @"attachments":attachment ? @[attachment] : @[]}];
        NSArray *wire = PCAttachmentInput(attachmentHistory, workspace, @"chatgpt", &error);
        NSDictionary *part = [wire.firstObject[@"content"] isKindOfClass:NSArray.class] && [wire.firstObject[@"content"] count] > 1 ? wire.firstObject[@"content"][1] : @{};
        results[@"attachment_import_and_wire"] = @([part[@"type"] isEqual:@"input_file"] && [part[@"file_data"] containsString:@"YXR0YWNobWVudCBmaXh0dXJl"]);
        NSData *png = [[NSData alloc] initWithBase64EncodedString:@"iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAE0lEQVR4nGP4z8DwnwGM/zMwAAAf7gP9NRsAMwAAAABJRU5ErkJggg==" options:0];
        NSDictionary *photo = PCAttachmentImportImage(png, workspace, &error);
        NSArray *photoWire = PCAttachmentInput(@[@{@"role":@"user", @"content":@"image", @"attachments":photo ? @[photo] : @[]}], workspace, @"chatgpt", &error);
        NSDictionary *photoPart = [photoWire.firstObject[@"content"] isKindOfClass:NSArray.class] && [photoWire.firstObject[@"content"] count] > 1 ? photoWire.firstObject[@"content"][1] : @{};
        results[@"image_import_and_wire"] = @([photoPart[@"type"] isEqual:@"input_image"] && [photoPart[@"image_url"] hasPrefix:@"data:image/jpeg;base64,"]);
        NSMutableArray *screenHistory=[NSMutableArray new];
        for(NSUInteger i=0;i<4;i++)[screenHistory addObject:@{@"type":@"function_call_output",@"call_id":[NSString stringWithFormat:@"screenshot-%lu",(unsigned long)i],@"output":@[@{@"type":@"input_text",@"text":@"Screenshot native size 750x1334"},photoPart]}];
        PCAgent *screenAgent=[PCAgent new];[screenAgent restoreHistory:screenHistory];NSArray *trimmed=[screenAgent historySnapshot];NSUInteger imageCount=0;BOOL idsPreserved=trimmed.count==4,actualSize=YES;
        for(NSUInteger i=0;i<trimmed.count;i++){idsPreserved&=[trimmed[i][@"call_id"] isEqual:screenHistory[i][@"call_id"]];for(NSDictionary *part in trimmed[i][@"output"])if([part[@"type"] isEqual:@"input_image"])imageCount++;if(i>=2)actualSize&=[trimmed[i][@"output"][0][@"text"] containsString:@"2×2"];}
        results[@"screen_history_images_bounded_and_ids_preserved"]=@(imageCount==2&&idsPreserved&&actualSize);
        if (![results[@"image_import_and_wire"] boolValue]) results[@"image_test_error"] = error.localizedDescription ?: @"UIKit 图片解码或 JPEG 转换未返回数据";
        NSString *projectPath = [temp stringByAppendingPathComponent:@"projects-test.json"];
        BOOL localizedNames=YES,automaticNames=YES,preservedNames=YES;
        NSArray *languages=@[@"zh-CN",@"en",@"ja",@"es",@"fr"];
        NSArray *chatNames=@[@"新对话",@"New chat",@"新しいチャット",@"Nueva conversación",@"Nouvelle conversation"];
        NSArray *projectNames=@[@"项目 2",@"Project 2",@"プロジェクト 2",@"Proyecto 2",@"Projet 2"];
        @try {for(NSUInteger language=0;language<languages.count;language++){
            PCSetProcessUILanguage(languages[language]);
            PCProjectStore *names=[[PCProjectStore alloc] initWithStoragePath:[temp stringByAppendingPathComponent:[NSString stringWithFormat:@"names-%lu.json",(unsigned long)language]]];
            localizedNames&=[names.currentChat[@"title"] isEqual:chatNames[language]];
            [names createProject:@"  "];localizedNames&=[names.currentProject[@"name"] isEqual:projectNames[language]]&&[names.currentChat[@"title"] isEqual:chatNames[language]];
            NSDictionary *numbered=[names createChat];localizedNames&=[numbered[@"title"] isEqual:[chatNames[language] stringByAppendingString:@" 2"]];
            PCSetProcessUILanguage(languages[(language+1)%languages.count]);[names createChat];
            preservedNames&=[names.currentProject[@"chats"][0][@"title"] isEqual:chatNames[language]]&&[names.currentChat[@"title"] isEqual:[chatNames[(language+1)%languages.count] stringByAppendingString:@" 3"]];
            NSArray *history=@[@{@"role":@"user",@"content":@"First message"}];[names saveHistory:history transcript:@""];
            automaticNames&=[names.currentChat[@"title"] isEqual:@"First message"];
            [names renameChat:names.currentChat[@"id"] title:chatNames[language]];[names saveHistory:history transcript:@""];
            preservedNames&=[names.currentChat[@"title"] isEqual:chatNames[language]];
            PCProjectStore *reload=[[PCProjectStore alloc] initWithStoragePath:names.persistentPath];preservedNames&=[reload.currentChat[@"title"] isEqual:chatNames[language]];
        }} @finally {PCSetProcessUILanguage(nil);}
        results[@"project_chat_default_names_five_languages"]=@(localizedNames);
        results[@"localized_chat_auto_title_from_first_message"]=@(automaticNames);
        results[@"localized_names_preserve_existing_and_manual_titles"]=@(preservedNames);
        PCProjectStore *store = [[PCProjectStore alloc] initWithStoragePath:projectPath];
        NSString *firstProject = store.currentProject[@"id"];
        NSString *firstChat = store.currentChat[@"id"];
        BOOL renamedProject=[store renameProject:firstProject name:@" 重命名测试 "]&&[store.currentProject[@"name"] isEqual:@"重命名测试"];
        BOOL renamedChat=[store renameChat:firstChat title:@"新对话 自定义名称"];
        [store saveHistory:@[@{@"role":@"user",@"content":@"不应该覆盖手动标题"}] transcript:@"fixture"];
        PCProjectStore *renameReload=[[PCProjectStore alloc] initWithStoragePath:projectPath];
        results[@"project_chat_rename_persistence"]=@(renamedProject&&renamedChat&&[renameReload.currentChat[@"title"] isEqual:@"新对话 自定义名称"]&&[renameReload.currentProject[@"name"] isEqual:@"重命名测试"]);
        results[@"rename_rejects_empty_or_oversize"]=@(![store renameChat:firstChat title:@"  "]&&![store renameProject:firstProject name:[@"x" stringByPaddingToLength:61 withString:@"x" startingAtIndex:0]]);
        NSDictionary *secondChat = [store createChat];
        BOOL removedFirstChat = [store deleteChat:firstChat] && [store.currentChat[@"id"] isEqual:secondChat[@"id"]];
        BOOL removedLastChat = [store deleteChat:secondChat[@"id"]] && [store.currentProject[@"chats"] count] == 1 && store.currentChat != nil;
        NSDictionary *secondProject = [store createProject:@"删除测试"];
        NSString *projectDirectory=PCRealPath(secondProject[@"workspace"]);BOOL projectDirectoryCreated=[fm fileExistsAtPath:projectDirectory];
        BOOL removedProject = [store deleteProject:secondProject[@"id"]] && [store.currentProject[@"id"] isEqual:firstProject];
        results[@"project_workspace_created_and_preserved"]=@(projectDirectoryCreated&&[fm fileExistsAtPath:projectDirectory]);
        BOOL replacedLastProject = [store deleteProject:firstProject] && store.projects.count == 1 && store.currentChat != nil;
        PCProjectStore *reloaded = [[PCProjectStore alloc] initWithStoragePath:projectPath];
        results[@"project_chat_delete_and_reload"] = @(removedFirstChat && removedLastChat && removedProject && replacedLastProject && reloaded.projects.count == 1 && reloaded.currentChat != nil);
    } @catch (NSException *exception) { results[@"error"] = exception.reason ?: @"异常"; }
    [NSUserDefaults.standardUserDefaults setVolatileDomain:previousDomain?:@{} forName:NSArgumentDomain];
    if (![fm removeItemAtPath:temp error:&error]) results[@"cleanup_error"] = error.localizedDescription;
    results[@"temporary_directory"] = temp;
    results[@"scope"] = @"离线自检；未更改 API Key 或 ChatGPT 凭据，未请求模型，不代表 AI 服务商联网或真机整体兼容性已通过。";
    return results;
}
