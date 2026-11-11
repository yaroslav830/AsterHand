#import <Foundation/Foundation.h>

extern NSString * const PCLanguageDidChangeNotification;
NSArray<NSString *> *PCUILanguages(void);
NSString *PCUILanguagePreference(void);
NSString *PCResolvedUILanguage(void);
NSString *PCUILanguageName(NSString *language);
BOOL PCSetUILanguage(NSString *language);
// Standalone overlay processes receive the resolved language from the app.
void PCSetProcessUILanguage(NSString *language);
NSString *PCLocalized(NSString *source);
