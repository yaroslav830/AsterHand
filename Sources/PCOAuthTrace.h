#import <Foundation/Foundation.h>

// Only fixed stage identifiers and numeric statuses. Never pass URLs or account data.
void PCOAuthTraceBegin(void);
void PCOAuthTrace(NSString *stage);
