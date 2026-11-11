#import "PCQuestion.h"
BOOL PCQuestionReplyMatches(NSDictionary *state,NSString *job,NSString *prompt,NSString *chat) {
    NSDictionary *question=[state[@"question"] isKindOfClass:NSDictionary.class]?state[@"question"]:nil;
    NSDictionary *context=[state[@"context"] isKindOfClass:NSDictionary.class]?state[@"context"]:nil;
    return job.length&&prompt.length&&chat.length&&[state[@"running"] boolValue]&&![state[@"cancelled"] boolValue]&&
        [state[@"id"] isEqual:job]&&[context[@"chat"] isEqual:chat]&&
        ([@[@"question",@"root_permission"] containsObject:question[@"kind"]])&&[question[@"id"] isEqual:prompt];
}
