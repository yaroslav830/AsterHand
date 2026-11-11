#import <UIKit/UIKit.h>
@interface PCOptionsPage : UITableViewController
@property(nonatomic,copy) NSArray<NSDictionary *> *options;
@property(nonatomic,copy) NSString *explanation;
@property(nonatomic,copy) void (^selectOption)(NSInteger);
@end
@interface PCTextEntryPage : UIViewController
@property(nonatomic,copy) NSString *fieldPlaceholder;
@property(nonatomic,copy) NSString *submitTitle;
@property(nonatomic,copy) NSString *initialText;
@property(nonatomic) NSUInteger maximumLength;
@property(nonatomic,copy) NSString *validationPattern;
@property(nonatomic) BOOL numeric;
@property(nonatomic,copy) void (^submit)(NSString *);
@end
@interface PCConfirmPage : UIViewController
@property(nonatomic,copy) NSString *message;
@property(nonatomic,copy) NSString *actionTitle;
@property(nonatomic,copy) void (^confirm)(void);
@end
