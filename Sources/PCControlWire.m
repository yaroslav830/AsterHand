#import "PCControl.h"
#import <CommonCrypto/CommonCryptor.h>
#import <CommonCrypto/CommonHMAC.h>
#import <Security/Security.h>
#include <arpa/inet.h>

static NSData *Secret(NSString *text) {
    if(![text isKindOfClass:NSString.class]||text.length!=64)return nil;
    NSMutableData *out=[NSMutableData new];for(NSUInteger i=0;i<64;i+=2){unsigned int byte;NSString *part=[text substringWithRange:NSMakeRange(i,2)];if([part rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"] invertedSet]].location!=NSNotFound||sscanf(part.UTF8String,"%02x",&byte)!=1)return nil;uint8_t b=(uint8_t)byte;[out appendBytes:&b length:1];}return out;
}
static NSData *MAC(NSData *key, NSData *value) {uint8_t digest[32];CCHmac(kCCHmacAlgSHA256,key.bytes,key.length,value.bytes,value.length,digest);return [NSData dataWithBytes:digest length:32];}
static NSData *Key(NSData *secret, NSString *purpose, NSString *direction) {return MAC(secret,[[NSString stringWithFormat:@"AgentGo/v1/%@/%@",purpose,direction] dataUsingEncoding:NSUTF8StringEncoding]);}
static NSData *Auth(NSData *secret, NSDictionary *packet, NSString *direction) {return MAC(Key(secret,@"authentication",direction),[[NSString stringWithFormat:@"v1\n%@\n%@\n%@\n%@",direction,packet[@"pair"],packet[@"iv"],packet[@"data"]] dataUsingEncoding:NSUTF8StringEncoding]);}
NSDictionary *PCControlSeal(NSString *pair, NSString *secretText, NSDictionary *payload, NSString *direction) {
    NSData *secret=Secret(secretText),*plain=[NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];if(!secret||!plain||plain.length>1400000)return nil;
    uint8_t iv[16];if(SecRandomCopyBytes(kSecRandomDefault,sizeof(iv),iv)!=errSecSuccess)return nil;
    NSMutableData *data=[NSMutableData dataWithLength:plain.length+16];size_t count=0;NSData *key=Key(secret,@"encryption",direction);
    if(CCCrypt(kCCEncrypt,kCCAlgorithmAES,kCCOptionPKCS7Padding,key.bytes,32,iv,plain.bytes,plain.length,data.mutableBytes,data.length,&count)!=kCCSuccess)return nil;data.length=count;
    NSMutableDictionary *packet=[@{@"v":@1,@"pair":pair,@"iv":[[NSData dataWithBytes:iv length:16] base64EncodedStringWithOptions:0],@"data":[data base64EncodedStringWithOptions:0]} mutableCopy];packet[@"mac"]=[Auth(secret,packet,direction) base64EncodedStringWithOptions:0];return packet;
}
NSDictionary *PCControlOpen(NSDictionary *packet, NSString *secretText, NSString *direction) {
    if(![packet isKindOfClass:NSDictionary.class]||![packet[@"v"] isEqual:@1]||![packet[@"pair"] isKindOfClass:NSString.class]||[packet[@"pair"] length]!=36||![[NSUUID alloc] initWithUUIDString:packet[@"pair"]])return nil;
    for(NSString *key in @[@"iv",@"data",@"mac"])if(![packet[key] isKindOfClass:NSString.class]||[packet[key] length]>2000000)return nil;
    NSData *secret=Secret(secretText);if(!secret)return nil;
    NSData *iv=[[NSData alloc] initWithBase64EncodedString:packet[@"iv"] options:0],*data=[[NSData alloc] initWithBase64EncodedString:packet[@"data"] options:0],*mac=[[NSData alloc] initWithBase64EncodedString:packet[@"mac"] options:0];
    if(iv.length!=16||!data.length||mac.length!=32)return nil;NSData *expected=Auth(secret,packet,direction);uint8_t difference=0;for(int i=0;i<32;i++)difference|=((uint8_t *)mac.bytes)[i]^((uint8_t *)expected.bytes)[i];if(difference)return nil;
    NSMutableData *plain=[NSMutableData dataWithLength:data.length+16];size_t count=0;NSData *key=Key(secret,@"encryption",direction);
    if(CCCrypt(kCCDecrypt,kCCAlgorithmAES,kCCOptionPKCS7Padding,key.bytes,32,iv.bytes,data.bytes,data.length,plain.mutableBytes,plain.length,&count)!=kCCSuccess)return nil;plain.length=count;
    NSDictionary *payload=[NSJSONSerialization JSONObjectWithData:plain options:0 error:nil];
    if(![payload isKindOfClass:NSDictionary.class]||![payload[@"id"] isKindOfClass:NSString.class]||[payload[@"id"] length]>80||![payload[@"ts"] isKindOfClass:NSNumber.class]||fabs(NSDate.date.timeIntervalSince1970-[payload[@"ts"] doubleValue])>90)return nil;
    return payload;
}
NSData *PCControlSealFrame(NSDictionary *frame,NSString *secretText,NSString *nonce) {
    NSData *secret=Secret(secretText),*jpeg=[[NSData alloc] initWithBase64EncodedString:frame[@"image_base64"]?:@"" options:0];if(!secret||!jpeg.length||jpeg.length>1024*1024)return nil;
    NSString *direction=[@"stream/" stringByAppendingString:nonce];uint32_t header[]={htonl([frame[@"stream_sequence"] unsignedIntValue]),htonl([frame[@"width"] unsignedIntValue]),htonl([frame[@"height"] unsignedIntValue]),htonl([frame[@"sequence"] unsignedIntValue])};NSMutableData *plain=[NSMutableData dataWithBytes:header length:16];[plain appendData:jpeg];
    uint8_t iv[16];if(SecRandomCopyBytes(kSecRandomDefault,16,iv))return nil;NSMutableData *cipher=[NSMutableData dataWithLength:plain.length+16];NSData *key=Key(secret,@"encryption",direction);size_t count=0;if(CCCrypt(kCCEncrypt,kCCAlgorithmAES,kCCOptionPKCS7Padding,key.bytes,32,iv,plain.bytes,plain.length,cipher.mutableBytes,cipher.length,&count)!=kCCSuccess)return nil;cipher.length=count;
    NSMutableData *packet=[NSMutableData dataWithBytes:iv length:16];[packet appendData:cipher];[packet appendData:MAC(Key(secret,@"authentication",direction),packet)];return packet;
}
NSDictionary *PCControlOpenFrame(NSData *data,NSString *secretText,NSString *nonce) {
    NSData *secret=Secret(secretText);if(!secret||data.length<80||data.length>2*1024*1024)return nil;NSString *direction=[@"stream/" stringByAppendingString:nonce];NSData *body=[data subdataWithRange:NSMakeRange(0,data.length-32)],*expected=MAC(Key(secret,@"authentication",direction),body);uint8_t difference=0;for(int i=0;i<32;i++)difference|=((uint8_t *)data.bytes)[data.length-32+i]^((uint8_t *)expected.bytes)[i];if(difference)return nil;
    NSData *key=Key(secret,@"encryption",direction);NSMutableData *plain=[NSMutableData dataWithLength:data.length];size_t count=0;if(CCCrypt(kCCDecrypt,kCCAlgorithmAES,kCCOptionPKCS7Padding,key.bytes,32,data.bytes,(uint8_t *)data.bytes+16,data.length-48,plain.mutableBytes,plain.length,&count)!=kCCSuccess||count<18)return nil;plain.length=count;uint32_t header[4];memcpy(header,plain.bytes,16);
    return @{@"stream_sequence":@(ntohl(header[0])),@"width":@(ntohl(header[1])),@"height":@(ntohl(header[2])),@"sequence":@(ntohl(header[3])),@"jpeg":[plain subdataWithRange:NSMakeRange(16,count-16)]};
}
