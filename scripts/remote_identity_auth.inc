// Included in the GPL TrollVNC adaptation. Device-pair grants replace IP trust.
#include <openssl/evp.h>
#include <openssl/pem.h>
#include <openssl/x509v3.h>
#include <openssl/rand.h>
#include <openssl/sha.h>
static NSMutableDictionary *pocketAuthenticated;
static NSString *pocketControlFile(NSString *name) {const char *root=jbroot("/var/mobile/Library/AgentGoControl");return root?[[NSString stringWithUTF8String:root] stringByAppendingPathComponent:name]:nil;}
static NSDictionary *pocketRead(NSString *path){NSData *data=[NSData dataWithContentsOfFile:path];id value=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;return [value isKindOfClass:NSDictionary.class]?value:@{};}
static NSDictionary *pocketPeer(NSString *identifier){NSDictionary *state=pocketRead(pocketControlFile(@"control.json"));if(![state[@"enabled"] boolValue]||![state[@"screen"] boolValue])return nil;if([state[@"background"] isEqual:@NO]){const char *foregroundPath=jbroot("/var/mobile/Library/AgentGoTasks/foreground.json");NSDictionary *foreground=foregroundPath?pocketRead([NSString stringWithUTF8String:foregroundPath]):@{};if(![foreground[@"active"] boolValue]||NSDate.date.timeIntervalSince1970-[foreground[@"updated"] doubleValue]>5)return nil;}for(NSDictionary *peer in state[@"peers"])if([peer[@"id"] isEqual:identifier]){if([peer[@"incoming"] isEqual:@NO])return nil;if([peer[@"incoming"] boolValue]&&[peer[@"mode"] isEqual:@"once"]&&[peer[@"expires_at"] doubleValue]<NSDate.date.timeIntervalSince1970)return nil;return peer;}return nil;}
static rfbBool pocketPasswordCheck(rfbClientPtr cl,const char *response,int length){
    if(length!=CHALLENGESIZE)return FALSE;
    NSDictionary *grants=pocketRead(pocketControlFile(@"vnc-grants.json"));double now=NSDate.date.timeIntervalSince1970;
    for(NSString *identifier in grants){NSDictionary *grant=grants[identifier];NSString *password=grant[@"password"];if([grant[@"expires"] doubleValue]<now||![password isKindOfClass:NSString.class]||password.length!=8||!pocketPeer(identifier))continue;
        unsigned char challenge[CHALLENGESIZE];memcpy(challenge,cl->authChallenge,CHALLENGESIZE);char pass[9]={0};strlcpy(pass,password.UTF8String,sizeof(pass));rfbEncryptBytes(challenge,pass);unsigned char mismatch=0;for(int i=0;i<CHALLENGESIZE;i++)mismatch|=challenge[i]^(unsigned char)response[i];
        if(!mismatch){if(!pocketAuthenticated)pocketAuthenticated=[NSMutableDictionary new];@synchronized(pocketAuthenticated){pocketAuthenticated[@(cl->sock)]=identifier;}cl->viewOnly=FALSE;return TRUE;}
    }return FALSE;
}
static void pocketMonitorClients(void){
    if(!gScreen)return;BOOL active=NO;NSString *name=@"AgentGo";rfbClientIteratorPtr iterator=rfbGetClientIterator(gScreen);rfbClientPtr client;
    while((client=rfbClientIteratorNext(iterator))){NSString *identifier;@synchronized(pocketAuthenticated){identifier=pocketAuthenticated[@(client->sock)];}if(!identifier)continue;NSDictionary *peer=pocketPeer(identifier);if(!peer)rfbCloseClient(client);else{active=YES;name=peer[@"name"]?:name;}}
    rfbReleaseClientIterator(iterator);NSData *data=[NSJSONSerialization dataWithJSONObject:@{@"name":name,@"active_until":active?@(NSDate.date.timeIntervalSince1970+3):@0} options:0 error:nil];NSString *file=pocketControlFile(@"vnc-presence.json");if(data&&[data writeToFile:file options:NSDataWritingAtomic error:nil]){chmod(file.fileSystemRepresentation,0600);chown(file.fileSystemRepresentation,501,501);}
}
static NSData *pocketBIOData(BIO *bio){char *bytes=NULL;long size=BIO_get_mem_data(bio,&bytes);return size>0?[NSData dataWithBytes:bytes length:(NSUInteger)size]:nil;}
static void pocketEnsureIdentity(NSString *directory){
    NSString *cert=[directory stringByAppendingPathComponent:@"server.pem"],*key=[directory stringByAppendingPathComponent:@"server-key.pem"],*config=[directory stringByAppendingPathComponent:@"phone.json"];
    if([NSFileManager.defaultManager fileExistsAtPath:cert]&&[NSFileManager.defaultManager fileExistsAtPath:key]&&[pocketRead(config)[@"password"] length]==8)return;
    EVP_PKEY_CTX *context=EVP_PKEY_CTX_new_id(EVP_PKEY_RSA,NULL);EVP_PKEY *privateKey=NULL;X509 *certificate=X509_new();
    if(!context||!certificate||EVP_PKEY_keygen_init(context)<=0||EVP_PKEY_CTX_set_rsa_keygen_bits(context,2048)<=0||EVP_PKEY_keygen(context,&privateKey)<=0){if(context)EVP_PKEY_CTX_free(context);if(certificate)X509_free(certificate);return;}
    X509_set_version(certificate,2);ASN1_INTEGER_set(X509_get_serialNumber(certificate),(long)(arc4random()&0x7fffffff));X509_gmtime_adj(X509_get_notBefore(certificate),-60);X509_gmtime_adj(X509_get_notAfter(certificate),315360000L);X509_set_pubkey(certificate,privateKey);
    X509_NAME *subject=X509_get_subject_name(certificate);X509_NAME_add_entry_by_txt(subject,"CN",MBSTRING_ASC,(unsigned char *)"pocketcodex.local",-1,-1,0);X509_set_issuer_name(certificate,subject);
    X509V3_CTX extensionContext;X509V3_set_ctx(&extensionContext,certificate,certificate,NULL,NULL,0);
    const char *names[]={"basicConstraints","subjectAltName","keyUsage"},*values[]={"critical,CA:TRUE","DNS:pocketcodex.local","critical,digitalSignature,keyEncipherment,keyCertSign"};
    for(int i=0;i<3;i++){X509_EXTENSION *extension=X509V3_EXT_conf(NULL,&extensionContext,(char *)names[i],(char *)values[i]);if(extension){X509_add_ext(certificate,extension,-1);X509_EXTENSION_free(extension);}}
    if(X509_sign(certificate,privateKey,EVP_sha256())>0){BIO *certBIO=BIO_new(BIO_s_mem()),*keyBIO=BIO_new(BIO_s_mem());if(certBIO&&keyBIO&&PEM_write_bio_X509(certBIO,certificate)&&PEM_write_bio_PrivateKey(keyBIO,privateKey,NULL,NULL,0,NULL,NULL)){
        unsigned char *der=NULL;int n=i2d_X509(certificate,&der);unsigned char digest[SHA256_DIGEST_LENGTH];SHA256(der,n,digest);OPENSSL_free(der);NSMutableString *fingerprint=[NSMutableString new];for(int i=0;i<SHA256_DIGEST_LENGTH;i++)[fingerprint appendFormat:@"%02x",digest[i]];
        unsigned char random[8];if(RAND_bytes(random,8)==1){NSMutableString *password=[NSMutableString new];const char alphabet[]="abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";for(int i=0;i<8;i++)[password appendFormat:@"%c",alphabet[random[i]%62]];
            [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];[pocketBIOData(keyBIO) writeToFile:key options:NSDataWritingAtomic error:nil];[pocketBIOData(certBIO) writeToFile:cert options:NSDataWritingAtomic error:nil];NSData *json=[NSJSONSerialization dataWithJSONObject:@{@"password":password,@"fingerprint":fingerprint} options:0 error:nil];[json writeToFile:config options:NSDataWritingAtomic error:nil];for(NSString *file in @[key,cert,config]){chmod(file.fileSystemRepresentation,0600);chown(file.fileSystemRepresentation,501,501);}
        }
    }if(certBIO)BIO_free(certBIO);if(keyBIO)BIO_free(keyBIO);}
    EVP_PKEY_free(privateKey);EVP_PKEY_CTX_free(context);X509_free(certificate);
}
