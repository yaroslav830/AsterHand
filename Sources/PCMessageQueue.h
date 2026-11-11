#import <Foundation/Foundation.h>
/* A message is context, never an answer to a pending question or approval. */
NSString *PCMessageEnqueue(NSString *directory, NSString *text, NSString *job, NSDictionary *context, NSString **error);
NSArray *PCMessagePending(NSString *directory);
void PCMessageAcknowledge(NSString *directory, NSDictionary *message, NSString *status, NSString *detail);
NSDictionary *PCMessageReceipt(NSString *directory, NSString *identifier);
