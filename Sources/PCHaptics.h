#import <UIKit/UIKit.h>
NSArray<NSDictionary *> *PCHapticStyles(void);
NSString *PCHapticNormalizeStyle(NSString *style);
// Optional explicit hint for standalone UIKit hosts; pocketoverlay is detected automatically.
void PCHapticSetStandaloneHost(BOOL standalone);
void PCHapticWithStyle(NSString *kind, NSString *style);
void PCHaptic(NSString *kind);
// Dispatch diagnostics only. No API can verify that the user physically felt a vibration.
NSDictionary *PCHapticLastEvent(void);
