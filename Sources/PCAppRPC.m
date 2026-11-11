#import "PCAppRPC.h"
#import "PCPlatform.h"
#include <sys/stat.h>
#include <unistd.h>

static NSString *RPCDirectory(void){return PCRealPath(@"/var/mobile/Library/PocketAgentControl/app-rpc");}
static BOOL RPCWrite(NSString *path,NSDictionary *value){NSData *data=[NSJSONSerialization dataWithJSONObject:value options:0 error:nil];if(!data||data.length>1500000)return NO;BOOL ok=[data writeToFile:path options:NSDataWritingAtomic error:nil];if(ok)chmod(path.fileSystemRepresentation,0600);return ok;}
static NSDictionary *RPCRead(NSString *path){struct stat st;if(lstat(path.fileSystemRepresentation,&st)||!S_ISREG(st.st_mode)||st.st_uid!=501||st.st_nlink!=1||(st.st_mode&0777)!=0600||st.st_size>1500000)return nil;NSData *data=[NSData dataWithContentsOfFile:path];id value=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;return [value isKindOfClass:NSDictionary.class]?value:nil;}
NSDictionary *PCAppRPCRequest(NSDictionary *arguments,BOOL (^cancel)(void)){
    NSString *directory=RPCDirectory();[NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];
    NSString *identifier=NSUUID.UUID.UUIDString.lowercaseString,*input=[directory stringByAppendingPathComponent:[identifier stringByAppendingString:@".request"]],*output=[directory stringByAppendingPathComponent:[identifier stringByAppendingString:@".response"]];
    if(!RPCWrite(input,@{@"id":identifier,@"created":@(NSDate.date.timeIntervalSince1970),@"arguments":arguments?:@{}}))return @{@"error":@"无法提交应用请求"};
    NSDictionary *result=nil;double until=NSProcessInfo.processInfo.systemUptime+12;
    while(NSProcessInfo.processInfo.systemUptime<until&&!(cancel&&cancel())){NSDictionary *reply=RPCRead(output);if([reply[@"id"] isEqual:identifier]){result=reply[@"result"];break;}usleep(50000);}
    [NSFileManager.defaultManager removeItemAtPath:input error:nil];[NSFileManager.defaultManager removeItemAtPath:output error:nil];
    return result?:@{@"error":@"应用未回应。请打开 AsterHand 后查看操作结果；不要自动重试写入操作。"};
}
void PCAppRPCServe(NSDictionary *(^handler)(NSDictionary *)){
    NSString *directory=RPCDirectory();NSArray *names=[NSFileManager.defaultManager contentsOfDirectoryAtPath:directory error:nil];NSUInteger count=0;
    for(NSString *name in names){NSString *path=[directory stringByAppendingPathComponent:name];if([@[@"response",@"claimed"] containsObject:name.pathExtension]){NSString *idpart=name.stringByDeletingPathExtension;if([name.pathExtension isEqual:@"claimed"])idpart=idpart.stringByDeletingPathExtension;struct stat st;if([[NSUUID alloc] initWithUUIDString:idpart]&&!lstat(path.fileSystemRepresentation,&st)&&S_ISREG(st.st_mode)&&st.st_uid==501&&st.st_nlink==1&&(st.st_mode&0777)==0600&&NSDate.date.timeIntervalSince1970-st.st_mtimespec.tv_sec>60)[NSFileManager.defaultManager removeItemAtPath:path error:nil];continue;}if(![name.pathExtension isEqual:@"request"]||![[NSUUID alloc] initWithUUIDString:name.stringByDeletingPathExtension])continue;NSDictionary *request=RPCRead(path);if(!request)continue;double age=NSDate.date.timeIntervalSince1970-[request[@"created"] doubleValue];if(age<0||age>10){[NSFileManager.defaultManager removeItemAtPath:path error:nil];continue;}if(++count>8)break;
        // Claim before executing. Timed-out operations are never replayed.
        NSString *claimed=[path stringByAppendingString:@".claimed"];if(![NSFileManager.defaultManager moveItemAtPath:path toPath:claimed error:nil])continue;
        NSDictionary *result=nil;@try{result=handler(request[@"arguments"]?:@{});}@catch(NSException *e){result=@{@"error":@"应用请求未能完成，请检查当前状态"};}
        RPCWrite([[directory stringByAppendingPathComponent:name.stringByDeletingPathExtension] stringByAppendingString:@".response"],@{@"id":request[@"id"]?:@"",@"result":result?:@{}});[NSFileManager.defaultManager removeItemAtPath:claimed error:nil];
    }
}
