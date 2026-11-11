#import <Foundation/Foundation.h>

BOOL PCIsRootHide(void);
BOOL PCIsRootful(void);
NSString *PCPrivilegedDirectory(void);
NSString *PCEnvironmentName(void);
NSString *PCRealPath(NSString *virtualPath);
NSString *PCVirtualPath(NSString *physicalPath);
NSString *PCShellPath(void);
NSString *PCJailbreakExecutable(NSString *path);
NSString *PCPathExplanation(void);
