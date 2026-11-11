#import "PCMessageQueue.h"
#include <sys/stat.h>
#include <unistd.h>
static BOOL ValidID(id value) {return [value isKindOfClass:NSString.class]&&[[NSUUID alloc] initWithUUIDString:value]!=nil;}
static NSString *Folder(NSString *directory,NSString *name) {
    NSString *path=[directory stringByAppendingPathComponent:name];
    if(![NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil])return nil;
    chmod(path.fileSystemRepresentation,0700);if(geteuid()==0)chown(path.fileSystemRepresentation,501,501);return path;
}
static NSDictionary *ReadJSON(NSString *path) {NSData *data=[NSData dataWithContentsOfFile:path];id item=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;return [item isKindOfClass:NSDictionary.class]?item:nil;}
static BOOL WriteJSON(NSString *path,NSDictionary *item) {NSData *data=[NSJSONSerialization dataWithJSONObject:item options:0 error:nil];if(!path||!data||![data writeToFile:path options:NSDataWritingAtomic error:nil])return NO;chmod(path.fileSystemRepresentation,0600);if(geteuid()==0)chown(path.fileSystemRepresentation,501,501);return YES;}
NSArray *PCMessagePending(NSString *directory) {
    NSString *folder=Folder(directory,@"messages");NSMutableArray *items=[NSMutableArray new];
    for(NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:folder error:nil]){
        if(![name.pathExtension isEqual:@"json"]||!ValidID(name.stringByDeletingPathExtension))continue;
        NSDictionary *item=ReadJSON([folder stringByAppendingPathComponent:name]);
        if(![item[@"id"] isEqual:name.stringByDeletingPathExtension])continue;
        if(![item[@"text"] isKindOfClass:NSString.class]||![item[@"job"] isKindOfClass:NSString.class]||![item[@"created"] isKindOfClass:NSNumber.class]||![item[@"context"] isKindOfClass:NSDictionary.class]){PCMessageAcknowledge(directory,item,@"error",@"消息格式无效");continue;}
        [items addObject:item];
    }
    [items sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [a[@"created"] compare:b[@"created"]];}];return items;
}
NSString *PCMessageEnqueue(NSString *directory,NSString *text,NSString *job,NSDictionary *context,NSString **error) {
    text=[text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *reason=nil;
    if(!text.length||text.length>4000)reason=@"消息需为 1–4000 字";
    else if(job&&!ValidID(job))reason=@"任务标识无效";
    else if(!job&&(![context[@"chat"] isKindOfClass:NSString.class]||![context[@"chat"] length]))reason=@"请先在应用中选择对话";
    else if(PCMessagePending(directory).count>=20)reason=@"待发消息过多，请稍后再试";
    if(reason){if(error)*error=reason;return nil;}
    NSString *identifier=NSUUID.UUID.UUIDString.lowercaseString;
    NSDictionary *item=@{@"id":identifier,@"text":text,@"job":job?:@"",@"context":context?:@{},@"created":@(NSDate.date.timeIntervalSince1970)};
    NSString *folder=Folder(directory,@"messages");
    if(!folder||!WriteJSON([folder stringByAppendingPathComponent:[identifier stringByAppendingString:@".json"]],item)){if(error)*error=@"无法保存消息，请重试";return nil;}return identifier;
}
NSDictionary *PCMessageReceipt(NSString *directory,NSString *identifier) {if(!ValidID(identifier))return nil;return ReadJSON([[directory stringByAppendingPathComponent:@"receipts"] stringByAppendingPathComponent:[identifier stringByAppendingString:@".json"]]);}
void PCMessageAcknowledge(NSString *directory,NSDictionary *message,NSString *status,NSString *detail) {
    if(!ValidID(message[@"id"]))return;
    NSString *folder=Folder(directory,@"receipts"),*name=[message[@"id"] stringByAppendingString:@".json"];
    if(!WriteJSON([folder stringByAppendingPathComponent:name],@{@"id":message[@"id"],@"status":status,@"detail":detail?:@"",@"updated":@(NSDate.date.timeIntervalSince1970)}))return;
    [NSFileManager.defaultManager removeItemAtPath:[[directory stringByAppendingPathComponent:@"messages"] stringByAppendingPathComponent:name] error:nil];
    for(NSString *old in [NSFileManager.defaultManager contentsOfDirectoryAtPath:folder error:nil]){NSString *path=[folder stringByAppendingPathComponent:old];NSDictionary *receipt=ReadJSON(path);if(receipt&&NSDate.date.timeIntervalSince1970-[receipt[@"updated"] doubleValue]>86400)[NSFileManager.defaultManager removeItemAtPath:path error:nil];}
}
