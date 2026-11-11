#import <Foundation/Foundation.h>
NSDictionary *PCTerminalRequest(NSString *action, NSDictionary *args, NSString *owner);
void PCTerminalCloseOwner(NSString *owner);
void PCTerminalStartMaintenance(void);
