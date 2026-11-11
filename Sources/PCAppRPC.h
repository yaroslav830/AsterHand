#import <Foundation/Foundation.h>
NSDictionary *PCAppRPCRequest(NSDictionary *arguments,BOOL (^cancel)(void));
void PCAppRPCServe(NSDictionary *(^handler)(NSDictionary *));
