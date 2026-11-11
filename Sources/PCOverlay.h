#import <Foundation/Foundation.h>

NSString *PCOverlayDirectory(void);
void PCOverlayPublish(BOOL enabled, BOOL running, BOOL paused);
NSString *PCOverlayTakeCommand(void);
void PCOverlayPrepareForAIScreen(void);
void PCOverlayFinishAIScreen(NSTimeInterval delay);
