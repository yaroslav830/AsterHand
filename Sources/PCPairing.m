#import "PCPairing.h"
#import "PCControl.h"
#import "PCPlatform.h"
#import "PCDiscovery.h"
#import <Security/Security.h>
#import <CommonCrypto/CommonDigest.h>
#include <arpa/inet.h>
#include <ifaddrs.h>
#include <spawn.h>
#include <unistd.h>
extern char **environ;
static NSString *Hash(NSData *data) { unsigned char bytes[CC_SHA256_DIGEST_LENGTH];CC_SHA256(data.bytes,(CC_LONG)data.length,bytes);NSMutableString *s=[NSMutableString new];for(int i=0;i<CC_SHA256_DIGEST_LENGTH;i++)[s appendFormat:@"%02x",bytes[i]];return s; }
static NSData *Decode(NSString *s) {return [s isKindOfClass:NSString.class]?[[NSData alloc] initWithBase64EncodedString:s options:0]:nil;}
BOOL PCPairIdentityValid(NSDictionary *identity) {if(![identity isKindOfClass:NSDictionary.class])return NO;NSData *public=Decode(identity[@"public_key"]);return public.length==65&&[Hash(public) isEqual:identity[@"device_id"]];}
NSDictionary *PCPairIdentity(void) {
    NSDictionary *stateAtRead=PCControlState();if(stateAtRead[@"error"])return nil;NSDictionary *identity=stateAtRead[@"identity"];
    if(!identity){
        SecKeyRef key=SecKeyCreateRandomKey((__bridge CFDictionaryRef)@{(__bridge id)kSecAttrKeyType:(__bridge id)kSecAttrKeyTypeECSECPrimeRandom,(__bridge id)kSecAttrKeySizeInBits:@256},NULL);if(!key)return nil;
        SecKeyRef pub=SecKeyCopyPublicKey(key);NSData *priv=CFBridgingRelease(SecKeyCopyExternalRepresentation(key,NULL)),*public=pub?CFBridgingRelease(SecKeyCopyExternalRepresentation(pub,NULL)):nil;if(pub)CFRelease(pub);CFRelease(key);if(!priv||!public)return nil;
        NSDictionary *generated=@{@"private_key":[priv base64EncodedStringWithOptions:0],@"public_key":[public base64EncodedStringWithOptions:0]};
        PCControlUpdate(^NSDictionary *(NSMutableDictionary *s){if(!s[@"identity"])s[@"identity"]=generated;return nil;});identity=PCControlState()[@"identity"];
    }
    NSData *public=Decode(identity[@"public_key"]);if(public.length!=65)return nil;
    NSDictionary *state=PCControlState();BOOL fixed=[state[@"pair_code_mode"] isEqual:@"fixed"];if(fixed&&[state[@"pair_code_fixed"] isKindOfClass:NSString.class]){NSMutableDictionary *copy=[state mutableCopy];copy[@"pair_code"]=state[@"pair_code_fixed"];state=copy;}else if([state[@"pair_code_expires"] doubleValue]<NSDate.date.timeIntervalSince1970){PCControlUpdate(^NSDictionary *(NSMutableDictionary *s){s[@"pair_code"]=[NSString stringWithFormat:@"%06u",arc4random_uniform(1000000)];s[@"pair_code_expires"]=@(NSDate.date.timeIntervalSince1970+120);return nil;});state=PCControlState();}
    return @{@"device_id":Hash(public),@"public_key":identity[@"public_key"],@"name":state[@"name"]?:@"AsterHand iPhone",@"port":@18769,@"pairing":@2,@"pair_code":state[@"pair_code"]?:@""};
}
static NSString *Secret(NSDictionary *remote,NSString *request) {
    if(![[NSUUID alloc] initWithUUIDString:request])return nil;NSData *public=Decode(remote[@"public_key"]);if(public.length!=65||![Hash(public) isEqual:remote[@"device_id"]])return nil;
    NSData *private=Decode(PCControlState()[@"identity"][@"private_key"]);if(!private)return nil;
    NSDictionary *base=@{(__bridge id)kSecAttrKeyType:(__bridge id)kSecAttrKeyTypeECSECPrimeRandom,(__bridge id)kSecAttrKeyClass:(__bridge id)kSecAttrKeyClassPrivate,(__bridge id)kSecAttrKeySizeInBits:@256};
    SecKeyRef key=SecKeyCreateWithData((__bridge CFDataRef)private,(__bridge CFDictionaryRef)base,NULL);NSMutableDictionary *attrs=[base mutableCopy];attrs[(__bridge id)kSecAttrKeyClass]=(__bridge id)kSecAttrKeyClassPublic;
    SecKeyRef peer=SecKeyCreateWithData((__bridge CFDataRef)public,(__bridge CFDictionaryRef)attrs,NULL);if(!key||!peer){if(key)CFRelease(key);if(peer)CFRelease(peer);return nil;}
    NSData *shared=CFBridgingRelease(SecKeyCopyKeyExchangeResult(key,kSecKeyAlgorithmECDHKeyExchangeStandard,peer,(__bridge CFDictionaryRef)@{},NULL));CFRelease(key);CFRelease(peer);if(!shared)return nil;
    NSMutableData *data=[[ @"AgentGo/pairing/v2" dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];uint8_t zero=0;[data appendBytes:&zero length:1];[data appendData:shared];[data appendData:[request dataUsingEncoding:NSUTF8StringEncoding]];return Hash(data);
}
static NSDictionary *Public(NSDictionary *r) {return @{@"id":r[@"id"],@"name":r[@"name"],@"device_id":r[@"device_id"],@"code":r[@"code"],@"status":r[@"status"],@"created":r[@"created"]};}
NSArray *PCPairPending(void) {NSMutableArray *out=[NSMutableArray new];double now=NSDate.date.timeIntervalSince1970;for(NSDictionary *r in [PCControlState()[@"pair_requests"] allValues])if([r[@"status"] isEqual:@"pending"]&&now-[r[@"created"] doubleValue]<120)[out addObject:Public(r)];return out;}
NSDictionary *PCPairDecide(NSString *identifier,NSString *mode) {
    if(![@[@"once",@"always",@"deny"] containsObject:mode])return @{@"error":@"无效的授权方式"};
    return PCControlUpdate(^NSDictionary *(NSMutableDictionary *s){
        NSMutableDictionary *requests=[s[@"pair_requests"] mutableCopy]?:[NSMutableDictionary new],*r=[requests[identifier] mutableCopy];if(!r||![r[@"status"] isEqual:@"pending"]||NSDate.date.timeIntervalSince1970-[r[@"created"] doubleValue]>120)return @{@"error":@"申请已过期"};
        r[@"status"]=[mode isEqual:@"deny"]?@"denied":@"accepted";r[@"mode"]=mode;requests[identifier]=r;s[@"pair_requests"]=requests;
        {NSMutableDictionary *trust=[s[@"trust"] mutableCopy]?:[NSMutableDictionary new];trust[r[@"device_id"]]=@{@"name":r[@"name"],@"public_key":r[@"public_key"],@"mode":[mode isEqual:@"once"]?@"ask":mode};s[@"trust"]=trust;}
        if(![mode isEqual:@"deny"]){NSMutableArray *peers=[NSMutableArray new];for(NSDictionary *p in s[@"peers"])if(!([p[@"device_id"] isEqual:r[@"device_id"]]&&![p[@"incoming"] isEqual:@NO]))[peers addObject:p];
            [peers addObject:@{@"id":identifier,@"key":r[@"key"],@"name":r[@"name"],@"host":r[@"host"],@"port":r[@"port"],@"device_id":r[@"device_id"],@"public_key":r[@"public_key"],@"mode":mode,@"incoming":@YES,@"expires_at":[mode isEqual:@"once"]?@(NSDate.date.timeIntervalSince1970+600):@0}];s[@"peers"]=peers;s[@"enabled"]=@YES;
        }
        return Public(r);
    });
}
NSDictionary *PCPairSetTrust(NSString *device,NSString *mode) {
    if(![@[@"ask",@"always",@"deny"] containsObject:mode])return @{@"error":@"授权方式无效"};
    return PCControlUpdate(^NSDictionary *(NSMutableDictionary *s){NSMutableDictionary *trust=[s[@"trust"] mutableCopy]?:[NSMutableDictionary new];NSDictionary *source=trust[device];for(NSDictionary *p in s[@"peers"])if([p[@"device_id"] isEqual:device])source=p;if(!source)return @{@"error":@"设备不存在"};
        trust[device]=@{@"name":source[@"name"],@"public_key":source[@"public_key"],@"mode":mode};s[@"trust"]=trust;NSMutableArray *peers=[NSMutableArray new];for(NSDictionary *p in s[@"peers"]){if([p[@"device_id"] isEqual:device]&&![p[@"incoming"] isEqual:@NO]){if(![mode isEqual:@"always"])continue;NSMutableDictionary *updated=[p mutableCopy];updated[@"mode"]=@"always";updated[@"expires_at"]=@0;[peers addObject:updated];}else[peers addObject:p];}s[@"peers"]=peers;return nil;});
}
NSDictionary *PCPairHandle(NSDictionary *body,NSString *address) {
    NSDictionary *local=PCPairIdentity();if(![body isKindOfClass:NSDictionary.class]||[body[@"v"] integerValue]!=2||!local)return nil;
    NSString *request=body[@"request"],*key=Secret(body[@"identity"],request);NSDictionary *payload=key?PCControlOpen(body[@"packet"],key,@"req"):nil;
    if(!payload||![body[@"packet"][@"pair"] isEqual:request]||![payload[@"args"][@"receiver_id"] isEqual:local[@"device_id"]]||![@[@"pair.request",@"pair.status"] containsObject:payload[@"method"]])return nil;
    NSDictionary *r=PCControlState()[@"pair_requests"][request];
    if(!r){if(![payload[@"method"] isEqual:@"pair.request"]||PCPairPending().count>=8)return nil;NSDictionary *a=payload[@"args"];if(![a[@"name"] isKindOfClass:NSString.class]||![a[@"name"] length]||[a[@"name"] length]>80||[a[@"port"] integerValue]<1||[a[@"port"] integerValue]>65535)return nil;
        unsigned int code=0;[[NSScanner scannerWithString:[key substringToIndex:8]] scanHexInt:&code];
        r=@{@"id":request,@"key":key,@"host":address,@"port":a[@"port"],@"name":a[@"name"],@"device_id":body[@"identity"][@"device_id"],@"public_key":body[@"identity"][@"public_key"],@"created":@(NSDate.date.timeIntervalSince1970),@"status":@"pending",@"code":[NSString stringWithFormat:@"%06u",code%1000000]};
        NSDictionary *saved=PCControlUpdate(^NSDictionary *(NSMutableDictionary *s){NSMutableDictionary *requests=[s[@"pair_requests"] mutableCopy]?:[NSMutableDictionary new];for(NSString *i in requests.allKeys)if(NSDate.date.timeIntervalSince1970-[requests[i][@"created"] doubleValue]>120)[requests removeObjectForKey:i];if(requests.count>=64)return @{@"error":@"申请过多"};requests[request]=r;s[@"pair_requests"]=requests;return nil;});if(saved[@"error"])return nil;
        NSString *mode=PCControlState()[@"trust"][r[@"device_id"]][@"mode"];
        if([@[@"always",@"deny"] containsObject:mode])PCPairDecide(request,mode);
        else{pid_t pid;NSString *uiopen=PCJailbreakExecutable(@"/usr/bin/uiopen");char *args[]={(char *)uiopen.fileSystemRepresentation,"pocketagent://open",NULL};int error=posix_spawn(&pid,args[0],NULL,NULL,args,environ);if(error)NSLog(@"AsterHand could not open connection consent: %d",error);}
    }else if(![r[@"key"] isEqual:key]||![r[@"device_id"] isEqual:body[@"identity"][@"device_id"]]||NSDate.date.timeIntervalSince1970-[r[@"created"] doubleValue]>120)return nil;
    r=PCControlState()[@"pair_requests"][request];NSMutableDictionary *result=[Public(r) mutableCopy];result[@"mode"]=r[@"mode"]?:NSNull.null;result[@"receiver"]=local;
    return PCControlSeal(request,key,@{@"id":payload[@"id"],@"ts":@(NSDate.date.timeIntervalSince1970),@"result":result},@"res");
}
static NSDictionary *HTTP(NSString *host,NSNumber *port,NSString *route,NSDictionary *body) {
    NSURLComponents *c=[NSURLComponents new];c.scheme=@"http";c.host=host;c.port=port;c.path=route;if(!c.URL)return nil;NSMutableURLRequest *q=[NSMutableURLRequest requestWithURL:c.URL cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:2];if(body){q.HTTPMethod=@"POST";q.HTTPBody=[NSJSONSerialization dataWithJSONObject:body options:0 error:nil];[q setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];}
    dispatch_semaphore_t done=dispatch_semaphore_create(0);__block NSDictionary *out;NSURLSessionConfiguration *config=NSURLSessionConfiguration.ephemeralSessionConfiguration;config.connectionProxyDictionary=@{};config.timeoutIntervalForResource=3;NSURLSession *session=[NSURLSession sessionWithConfiguration:config];[[session dataTaskWithRequest:q completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){if(!error&&[(NSHTTPURLResponse *)response statusCode]==200&&data.length<65536)out=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];dispatch_semaphore_signal(done);}] resume];dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC));[session invalidateAndCancel];return [out isKindOfClass:NSDictionary.class]?out:nil;
}
NSArray *PCPairDiscover(void) {
    return PCDiscoveryRun(nil)[@"devices"];
}
NSDictionary *PCPairBegin(NSDictionary *remote) {
    NSDictionary *local=PCPairIdentity();NSString *identifier=NSUUID.UUID.UUIDString.lowercaseString,*key=Secret(remote,identifier);if(!key||[remote[@"device_id"] isEqual:local[@"device_id"]])return @{@"error":@"设备身份无效"};
    PCControlUpdate(^NSDictionary *(NSMutableDictionary *s){NSMutableDictionary *out=[s[@"outgoing_requests"] mutableCopy]?:[NSMutableDictionary new];for(NSString *i in out.allKeys)if(NSDate.date.timeIntervalSince1970-[out[i][@"created"] doubleValue]>120)[out removeObjectForKey:i];out[identifier]=@{@"id":identifier,@"key":key,@"remote":remote,@"created":@(NSDate.date.timeIntervalSince1970),@"first":@YES};s[@"outgoing_requests"]=out;return nil;});return PCPairPoll(identifier);
}
NSDictionary *PCPairPoll(NSString *identifier) {
    NSDictionary *r=PCControlState()[@"outgoing_requests"][identifier];if(!r||NSDate.date.timeIntervalSince1970-[r[@"created"] doubleValue]>120)return @{@"error":@"申请已过期"};NSDictionary *local=PCPairIdentity(),*remote=r[@"remote"];NSString *nonce=NSUUID.UUID.UUIDString.lowercaseString;
    NSDictionary *packet=PCControlSeal(identifier,r[@"key"],@{@"id":nonce,@"ts":@(NSDate.date.timeIntervalSince1970),@"method":[r[@"first"] boolValue]?@"pair.request":@"pair.status",@"args":@{@"receiver_id":remote[@"device_id"],@"name":local[@"name"],@"port":local[@"port"]}},@"req");
    NSDictionary *envelope=HTTP(remote[@"host"],remote[@"port"],@"/pair",@{@"v":@2,@"request":identifier,@"identity":local,@"packet":packet});NSDictionary *opened=envelope?PCControlOpen(envelope,r[@"key"],@"res"):nil,*result=opened[@"result"];
    if(![envelope[@"pair"] isEqual:identifier]||![opened[@"id"] isEqual:nonce]||![result[@"receiver"][@"device_id"] isEqual:remote[@"device_id"]])return @{@"error":@"申请失败或身份不匹配"};
    PCControlUpdate(^NSDictionary *(NSMutableDictionary *s){NSMutableDictionary *out=[s[@"outgoing_requests"] mutableCopy],*updated=[r mutableCopy];updated[@"first"]=@NO;out[identifier]=updated;
        if([result[@"status"] isEqual:@"accepted"]){NSMutableArray *peers=[NSMutableArray new];for(NSDictionary *p in s[@"peers"])if(!([p[@"device_id"] isEqual:remote[@"device_id"]]&&![p[@"incoming"] boolValue]))[peers addObject:p];[peers addObject:@{@"id":identifier,@"key":r[@"key"],@"host":remote[@"host"],@"port":remote[@"port"],@"name":remote[@"name"],@"device_id":remote[@"device_id"],@"public_key":remote[@"public_key"],@"mode":result[@"mode"],@"incoming":@NO}];s[@"peers"]=peers;[out removeObjectForKey:identifier];}else if([result[@"status"] isEqual:@"denied"])[out removeObjectForKey:identifier];s[@"outgoing_requests"]=out;return nil;});return result;
}
void PCControlRelease(NSString *peer) {
    PCControlRequest(peer,@"session.close",@{},nil);PCControlUpdate(^NSDictionary *(NSMutableDictionary *s){NSMutableArray *peers=[s[@"peers"] mutableCopy];NSIndexSet *indices=[peers indexesOfObjectsPassingTest:^BOOL(NSDictionary *p,NSUInteger index,BOOL *stop){return [p[@"id"] isEqual:peer]&&[p[@"mode"] isEqual:@"once"]; }];[peers removeObjectsAtIndexes:indices];s[@"peers"]=peers;return nil;});
}
