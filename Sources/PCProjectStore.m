#import "PCProjectStore.h"
#import "PCSupport.h"
#import "PCPlatform.h"
#import "PCLocalization.h"

@interface PCProjectStore ()
@property(nonatomic, strong) NSMutableDictionary *state;
@property(nonatomic, copy) NSString *overrideStoragePath;
@end

@implementation PCProjectStore
- (instancetype)init {
    return [self initWithStoragePath:nil];
}
- (instancetype)initWithStoragePath:(NSString *)path {
    if ((self = [super init])) { _overrideStoragePath = [path copy]; [self load]; }
    return self;
}

- (NSString *)persistentPath {return [self storagePath];}
- (NSString *)storagePath {
    if (self.overrideStoragePath.length) return self.overrideStoragePath;
    NSArray *urls = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask];
    NSString *directory = [[urls.firstObject path] stringByAppendingPathComponent:@"PocketAgent"];
    [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];
    return [directory stringByAppendingPathComponent:@"projects.json"];
}

- (NSString *)newID { return NSUUID.UUID.UUIDString.lowercaseString; }

- (NSMutableDictionary *)emptyChat {
    return [@{@"id":[self newID], @"title":PCLocalized(@"新对话"), @"autoTitle":@YES, @"history":[NSMutableArray new], @"transcript":@""} mutableCopy];
}

- (NSMutableDictionary *)emptyProject:(NSString *)name workspace:(NSString *)workspace {
    NSMutableDictionary *project = [@{@"id":[self newID], @"name":name, @"workspace":workspace,
        @"chats":[NSMutableArray new]} mutableCopy];
    [project[@"chats"] addObject:[self emptyChat]];
    project[@"currentChatID"] = project[@"chats"][0][@"id"];
    return project;
}

- (void)load {
    NSData *data = [NSData dataWithContentsOfFile:[self storagePath]];
    id saved = data ? [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil] : nil;
    if ([saved isKindOfClass:NSDictionary.class] && [saved[@"projects"] isKindOfClass:NSArray.class] && [saved[@"projects"] count]) {
        self.state = [saved mutableCopy];
    } else {
        NSString *base = PCWorkspace();
        self.state = [@{@"projects":[NSMutableArray new]} mutableCopy];
        NSMutableDictionary *project = [self emptyProject:PCLocalized(@"默认项目") workspace:base];
        [self.state[@"projects"] addObject:project];
        self.state[@"currentProjectID"] = project[@"id"];
        self.state[@"defaultProjectID"] = project[@"id"];
        self.state[@"currentChatID"] = project[@"currentChatID"];
        [self persist];
    }
    if (![self.state[@"defaultProjectID"] isKindOfClass:NSString.class]) {
        for (NSDictionary *project in self.state[@"projects"]) {
            if ([project[@"name"] isEqual:@"默认项目"]) { self.state[@"defaultProjectID"] = project[@"id"]; break; }
        }
    }
    if (![self currentProject]) {
        NSDictionary *first = [self projects].firstObject;
        self.state[@"currentProjectID"] = first[@"id"];
        self.state[@"currentChatID"] = first[@"currentChatID"];
    }
    if (![self currentChat]) [self createChat];
    [self syncDefaultWorkspace];
    NSString *workspace=self.currentProject[@"workspace"];if(workspace.isAbsolutePath)[NSFileManager.defaultManager createDirectoryAtPath:PCRealPath(workspace) withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];
}

- (NSArray<NSDictionary *> *)projects {
    NSArray *items = [self.state[@"projects"] isKindOfClass:NSArray.class] ? self.state[@"projects"] : @[];
    return [[NSArray alloc] initWithArray:items copyItems:YES];
}

- (NSDictionary *)currentProject {
    NSString *identifier = self.state[@"currentProjectID"];
    for (NSDictionary *project in self.state[@"projects"]) if ([project[@"id"] isEqual:identifier]) return project;
    return nil;
}

- (NSDictionary *)currentChat {
    NSDictionary *project = [self currentProject];
    NSString *identifier = self.state[@"currentChatID"] ?: project[@"currentChatID"];
    for (NSDictionary *chat in project[@"chats"]) if ([chat[@"id"] isEqual:identifier]) return chat;
    return nil;
}

- (BOOL)selectProject:(NSString *)projectID {
    for (NSDictionary *project in self.state[@"projects"]) if ([project[@"id"] isEqual:projectID]) {
        self.state[@"currentProjectID"] = projectID;
        self.state[@"currentChatID"] = project[@"currentChatID"] ?: [project[@"chats"] firstObject][@"id"];
        [self persist]; return YES;
    }
    return NO;
}

- (BOOL)selectChat:(NSString *)chatID {
    NSMutableDictionary *project = nil;
    for (NSMutableDictionary *candidate in self.state[@"projects"]) {
        for (NSDictionary *chat in candidate[@"chats"]) if ([chat[@"id"] isEqual:chatID]) project = candidate;
    }
    if (!project) return NO;
    project[@"currentChatID"] = chatID;
    self.state[@"currentProjectID"] = project[@"id"];
    self.state[@"currentChatID"] = chatID;
    [self persist]; return YES;
}

- (NSDictionary *)createProject:(NSString *)name {
    NSString *clean = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!clean.length) clean = [PCLocalized(@"项目 {number}") stringByReplacingOccurrencesOfString:@"{number}" withString:[@([self.state[@"projects"] count]+1) stringValue]];
    if (clean.length > 60) clean = [clean substringToIndex:60];
    NSString *identifier = [self newID];
    NSString *workspace = [[PCWorkspace() stringByAppendingPathComponent:@"Projects"] stringByAppendingPathComponent:identifier];
    if(![NSFileManager.defaultManager createDirectoryAtPath:PCRealPath(workspace) withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil])return nil;
    NSMutableDictionary *project = [self emptyProject:clean workspace:workspace];
    project[@"id"] = identifier;
    [self.state[@"projects"] addObject:project];
    self.state[@"currentProjectID"] = identifier;
    self.state[@"currentChatID"] = project[@"currentChatID"];
    [self persist]; return project;
}

- (NSDictionary *)createChat {
    NSMutableDictionary *project = [[self currentProject] mutableCopy];
    if (!project) return nil;
    NSMutableArray *projects = [self.state[@"projects"] mutableCopy];
    NSUInteger index = [projects indexOfObjectPassingTest:^BOOL(NSDictionary *item, NSUInteger idx, BOOL *stop) { return [item[@"id"] isEqual:project[@"id"]]; }];
    if (index == NSNotFound) return nil;
    NSMutableArray *chats = [project[@"chats"] mutableCopy] ?: [NSMutableArray new];
    NSMutableDictionary *chat = [self emptyChat];
    chat[@"title"] = [PCLocalized(@"新对话 {number}") stringByReplacingOccurrencesOfString:@"{number}" withString:[@(chats.count+1) stringValue]];
    [chats addObject:chat]; project[@"chats"] = chats; project[@"currentChatID"] = chat[@"id"];
    projects[index] = project; self.state[@"projects"] = projects;
    self.state[@"currentProjectID"] = project[@"id"]; self.state[@"currentChatID"] = chat[@"id"];
    [self persist]; return chat;
}

- (BOOL)deleteProject:(NSString *)projectID {
    NSMutableArray *projects = [self.state[@"projects"] mutableCopy];
    NSUInteger index = [projects indexOfObjectPassingTest:^BOOL(NSDictionary *item, NSUInteger idx, BOOL *stop) {
        return [item[@"id"] isEqual:projectID];
    }];
    if (index == NSNotFound) return NO;
    [projects removeObjectAtIndex:index];
    if (!projects.count) {
        NSMutableDictionary *replacement = [self emptyProject:PCLocalized(@"默认项目") workspace:PCWorkspace()];
        [projects addObject:replacement];
        self.state[@"defaultProjectID"] = replacement[@"id"];
    } else if ([self.state[@"defaultProjectID"] isEqual:projectID]) {
        self.state[@"defaultProjectID"] = @"";
    }
    self.state[@"projects"] = projects;
    if ([self.state[@"currentProjectID"] isEqual:projectID]) {
        NSDictionary *next = projects.firstObject;
        self.state[@"currentProjectID"] = next[@"id"];
        self.state[@"currentChatID"] = next[@"currentChatID"];
    }
    [self persist];
    return YES;
}

- (BOOL)deleteChat:(NSString *)chatID {
    NSMutableArray *projects = [self.state[@"projects"] mutableCopy];
    for (NSUInteger i = 0; i < projects.count; i++) {
        NSMutableDictionary *project = [projects[i] mutableCopy];
        NSMutableArray *chats = [project[@"chats"] mutableCopy];
        NSUInteger index = [chats indexOfObjectPassingTest:^BOOL(NSDictionary *item, NSUInteger idx, BOOL *stop) {
            return [item[@"id"] isEqual:chatID];
        }];
        if (index == NSNotFound) continue;
        [chats removeObjectAtIndex:index];
        if (!chats.count) [chats addObject:[self emptyChat]];
        project[@"chats"] = chats;
        if ([project[@"currentChatID"] isEqual:chatID]) project[@"currentChatID"] = [chats.firstObject objectForKey:@"id"];
        projects[i] = project;
        self.state[@"projects"] = projects;
        if ([self.state[@"currentProjectID"] isEqual:project[@"id"]]) self.state[@"currentChatID"] = project[@"currentChatID"];
        [self persist];
        return YES;
    }
    return NO;
}

- (BOOL)syncDefaultWorkspace {
    NSString *identifier = self.state[@"defaultProjectID"];
    if (![identifier isKindOfClass:NSString.class]) return NO;
    for (NSMutableDictionary *project in self.state[@"projects"]) {
        if (![project[@"id"] isEqual:identifier]) continue;
        NSString *workspace = PCWorkspace();
        if (![project[@"workspace"] isEqual:workspace]) { project[@"workspace"] = workspace; [self persist]; }
        return [self.state[@"currentProjectID"] isEqual:identifier];
    }
    return NO;
}

- (void)updateCurrentChat:(void (^)(NSMutableDictionary *chat))update {
    NSMutableArray *projects = [self.state[@"projects"] mutableCopy];
    for (NSUInteger i = 0; i < projects.count; i++) {
        NSMutableDictionary *project = [projects[i] mutableCopy];
        if (![project[@"id"] isEqual:self.state[@"currentProjectID"]]) continue;
        NSMutableArray *chats = [project[@"chats"] mutableCopy];
        for (NSUInteger j = 0; j < chats.count; j++) {
            NSMutableDictionary *chat = [chats[j] mutableCopy];
            if (![chat[@"id"] isEqual:self.state[@"currentChatID"]]) continue;
            update(chat); chats[j] = chat; project[@"chats"] = chats; projects[i] = project;
            self.state[@"projects"] = projects; [self persist]; return;
        }
    }
}

- (BOOL)renameProject:(NSString *)projectID name:(NSString *)name {
    NSString *clean=[name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];if(!clean.length||clean.length>60)return NO;
    NSMutableArray *projects=[self.state[@"projects"] mutableCopy];for(NSUInteger i=0;i<projects.count;i++){NSMutableDictionary *project=[projects[i] mutableCopy];if([project[@"id"] isEqual:projectID]){project[@"name"]=clean;projects[i]=project;self.state[@"projects"]=projects;[self persist];return YES;}}return NO;
}
- (BOOL)renameChat:(NSString *)chatID title:(NSString *)title {
    NSString *clean=[title stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];if(!clean.length||clean.length>80)return NO;
    NSMutableArray *projects=[self.state[@"projects"] mutableCopy];for(NSUInteger i=0;i<projects.count;i++){NSMutableDictionary *project=[projects[i] mutableCopy];NSMutableArray *chats=[project[@"chats"] mutableCopy];for(NSUInteger j=0;j<chats.count;j++){NSMutableDictionary *chat=[chats[j] mutableCopy];if([chat[@"id"] isEqual:chatID]){chat[@"title"]=clean;chat[@"manualTitle"]=@YES;chat[@"autoTitle"]=@NO;chats[j]=chat;project[@"chats"]=chats;projects[i]=project;self.state[@"projects"]=projects;[self persist];return YES;}}}return NO;
}
- (void)saveTranscript:(NSString *)transcript {
    NSString *text = transcript ?: @"";
    if (text.length > 120000) text = [text substringFromIndex:text.length - 120000];
    [self updateCurrentChat:^(NSMutableDictionary *chat) { chat[@"transcript"] = text; }];
}

- (void)saveHistory:(NSArray *)history transcript:(NSString *)transcript {
    NSData *historyData = [NSJSONSerialization dataWithJSONObject:history ?: @[] options:0 error:nil];
    NSArray *safeHistory = historyData.length <= 700 * 1024 ? (history ?: @[]) : @[];
    NSString *text = transcript ?: @"";
    if (text.length > 120000) text = [text substringFromIndex:text.length - 120000];
    [self updateCurrentChat:^(NSMutableDictionary *chat) {
        chat[@"history"] = safeHistory;
        chat[@"transcript"] = text;
        NSString *title = [chat[@"title"] isKindOfClass:NSString.class] ? chat[@"title"] : @"";
        // Persist intent separately from the translated title. Old indexes only
        // used the exact Chinese placeholder, with an optional numeric suffix.
        BOOL automatic=chat[@"autoTitle"]?[chat[@"autoTitle"] boolValue]:[title rangeOfString:@"^新对话(?: [0-9]+)?$" options:NSRegularExpressionSearch].location!=NSNotFound;
        if (automatic && ![chat[@"manualTitle"] boolValue]) {
            for (NSDictionary *item in safeHistory) {
                if ([item[@"role"] isEqual:@"user"] && [item[@"content"] isKindOfClass:NSString.class]) {
                    NSString *candidate = [[item[@"content"] componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet].firstObject stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
                    if (candidate.length) {chat[@"title"] = candidate.length > 36 ? [[candidate substringToIndex:36] stringByAppendingString:@"…"] : candidate;chat[@"autoTitle"]=@NO;}
                    break;
                }
            }
        }
    }];
}

- (void)persist {
    NSData *json = [NSJSONSerialization dataWithJSONObject:self.state options:NSJSONWritingPrettyPrinted error:nil];
    if (json.length > 16 * 1024 * 1024) return;
    [json writeToFile:[self storagePath] options:NSDataWritingAtomic error:nil];
}
@end
