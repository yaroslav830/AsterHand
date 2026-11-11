#import <Foundation/Foundation.h>

@interface PCProjectStore : NSObject
- (instancetype)initWithStoragePath:(NSString *)path;
- (NSString *)persistentPath;
@property(nonatomic, readonly, copy) NSArray<NSDictionary *> *projects;
@property(nonatomic, readonly, copy) NSDictionary *currentProject;
@property(nonatomic, readonly, copy) NSDictionary *currentChat;
- (BOOL)selectProject:(NSString *)projectID;
- (BOOL)selectChat:(NSString *)chatID;
- (NSDictionary *)createProject:(NSString *)name;
- (NSDictionary *)createChat;
- (BOOL)deleteProject:(NSString *)projectID;
- (BOOL)deleteChat:(NSString *)chatID;
- (BOOL)renameProject:(NSString *)projectID name:(NSString *)name;
- (BOOL)renameChat:(NSString *)chatID title:(NSString *)title;
- (BOOL)syncDefaultWorkspace;
- (void)saveTranscript:(NSString *)transcript;
- (void)saveHistory:(NSArray *)history transcript:(NSString *)transcript;
@end
