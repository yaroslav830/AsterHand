#import <Foundation/Foundation.h>

NSDictionary *PCAttachmentImport(NSURL *source, NSString *workspace, NSError **error);
NSDictionary *PCAttachmentImportImage(NSData *data, NSString *workspace, NSError **error);
NSArray *PCAttachmentInput(NSArray *history, NSString *workspace, NSString *provider, NSError **error);
