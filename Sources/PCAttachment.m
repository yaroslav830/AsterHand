#import "PCAttachment.h"
#import "PCPlatform.h"
#import <UIKit/UIKit.h>

static NSError *PCFileError(NSString *message) {
    return [NSError errorWithDomain:@"PocketAgent.Attachment" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
}

static NSDictionary *PCFileType(NSString *extension) {
    static NSDictionary *types;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ types = @{
        @"jpg":@"image/jpeg", @"jpeg":@"image/jpeg", @"png":@"image/png", @"webp":@"image/webp", @"gif":@"image/gif",
        @"pdf":@"application/pdf", @"txt":@"text/plain", @"md":@"text/markdown", @"json":@"application/json",
        @"html":@"text/html", @"xml":@"application/xml", @"csv":@"text/csv", @"rtf":@"application/rtf",
        @"doc":@"application/msword", @"docx":@"application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        @"xls":@"application/vnd.ms-excel", @"xlsx":@"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        @"ppt":@"application/vnd.ms-powerpoint", @"pptx":@"application/vnd.openxmlformats-officedocument.presentationml.presentation",
        @"py":@"text/plain", @"js":@"text/plain", @"ts":@"text/plain", @"m":@"text/plain", @"h":@"text/plain",
        @"c":@"text/plain", @"cpp":@"text/plain", @"swift":@"text/plain", @"sh":@"text/plain", @"yaml":@"text/plain", @"yml":@"text/plain"
    }; });
    return types[extension.lowercaseString] ? @{@"mime":types[extension.lowercaseString], @"kind":[types[extension.lowercaseString] hasPrefix:@"image/"] ? @"image" : @"file"} : nil;
}

NSDictionary *PCAttachmentImport(NSURL *source, NSString *workspace, NSError **error) {
    NSString *name = source.lastPathComponent ?: @"";
    NSString *extension = name.pathExtension.lowercaseString;
    NSDictionary *type = PCFileType(extension);
    if (!type) { if (error) *error = PCFileError(@"不支持这种附件格式。可选择图片、PDF、文本、代码或常见办公文档。"); return nil; }
    BOOL scoped = [source startAccessingSecurityScopedResource];
    @try {
        NSNumber *size = nil;
        [source getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
        if (size.unsignedLongLongValue > 8 * 1024 * 1024) { if (error) *error = PCFileError(@"单个附件不能超过 8 MB。"); return nil; }
        NSString *directory = [PCRealPath(workspace) stringByAppendingPathComponent:@"Attachments"];
        NSFileManager *fm = NSFileManager.defaultManager;
        if (![fm createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:error]) return nil;
        NSString *stored = [[NSUUID.UUID.UUIDString stringByAppendingString:@"."] stringByAppendingString:extension];
        NSString *destination = [directory stringByAppendingPathComponent:stored];
        if (![fm copyItemAtURL:source toURL:[NSURL fileURLWithPath:destination] error:error]) return nil;
        NSDictionary *attributes = [fm attributesOfItemAtPath:destination error:error];
        if (!attributes) { [fm removeItemAtPath:destination error:nil]; return nil; }
        if ([attributes fileSize] > 8 * 1024 * 1024) {
            [fm removeItemAtPath:destination error:nil];
            if (error) *error = PCFileError(@"单个附件不能超过 8 MB。"); return nil;
        }
        [fm setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:destination error:nil];
        return @{@"name":name, @"stored":stored, @"mime":type[@"mime"], @"kind":type[@"kind"], @"size":@([attributes fileSize])};
    } @finally { if (scoped) [source stopAccessingSecurityScopedResource]; }
}

NSDictionary *PCAttachmentImportImage(NSData *data, NSString *workspace, NSError **error) {
    UIImage *image = [UIImage imageWithData:data];
    NSData *jpeg = image ? UIImageJPEGRepresentation(image, 0.82) : nil;
    if (!jpeg || jpeg.length > 8 * 1024 * 1024) { if (error) *error = PCFileError(@"图片无法读取或超过 8 MB。"); return nil; }
    NSString *directory = [PCRealPath(workspace) stringByAppendingPathComponent:@"Attachments"];
    if (![NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:error]) return nil;
    NSString *stored = [NSUUID.UUID.UUIDString stringByAppendingString:@".jpg"];
    NSString *path = [directory stringByAppendingPathComponent:stored];
    if (![jpeg writeToFile:path options:NSDataWritingAtomic error:error]) return nil;
    [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:path error:nil];
    return @{@"name":@"图片.jpg", @"stored":stored, @"mime":@"image/jpeg", @"kind":@"image", @"size":@(jpeg.length)};
}

NSArray *PCAttachmentInput(NSArray *history, NSString *workspace, NSString *provider, NSError **error) {
    NSMutableArray *wire = [NSMutableArray new];
    NSUInteger totalFileBytes = 0;
    NSString *directory = [[PCRealPath(workspace) stringByAppendingPathComponent:@"Attachments"] stringByResolvingSymlinksInPath];
    for (NSDictionary *item in history) {
        NSArray *files = [item[@"attachments"] isKindOfClass:NSArray.class] ? item[@"attachments"] : nil;
        if (!files.count) { [wire addObject:item]; continue; }
        if (![provider isEqual:@"openai"] && ![provider isEqual:@"chatgpt"]) {
            if (error) *error = PCFileError(@"当前附件发送支持 OpenAI API 和 ChatGPT 登录。请切换服务商后重试。"); return nil;
        }
        NSMutableArray *content = [NSMutableArray new];
        NSString *message = [item[@"content"] isKindOfClass:NSString.class] ? item[@"content"] : @"";
        [content addObject:@{@"type":@"input_text", @"text":message.length ? message : @"请分析附件。"}];
        for (NSDictionary *file in files) {
            NSString *stored = [file[@"stored"] isKindOfClass:NSString.class] ? file[@"stored"] : @"";
            if (!stored.length || ![stored.lastPathComponent isEqual:stored] || !PCFileType(stored.pathExtension)) {
                if (error) *error = PCFileError(@"附件记录无效。"); return nil;
            }
            NSString *path = [[directory stringByAppendingPathComponent:stored] stringByResolvingSymlinksInPath];
            if (![path hasPrefix:[directory stringByAppendingString:@"/"]]) { if (error) *error = PCFileError(@"附件路径超出当前项目。"); return nil; }
            NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:error];
            if (!data || data.length > 8 * 1024 * 1024) { if (error) *error = PCFileError(@"附件不存在或超过 8 MB。"); return nil; }
            totalFileBytes += data.length;
            if (totalFileBytes > 40 * 1024 * 1024) { if (error) *error = PCFileError(@"当前对话累计附件超过 40 MB。请新建对话后再发送。"); return nil; }
            NSString *mime = PCFileType(stored.pathExtension)[@"mime"];
            NSString *url = [NSString stringWithFormat:@"data:%@;base64,%@", mime, [data base64EncodedStringWithOptions:0]];
            if ([mime hasPrefix:@"image/"]) [content addObject:@{@"type":@"input_image", @"image_url":url}];
            else [content addObject:@{@"type":@"input_file", @"filename":file[@"name"] ?: stored, @"file_data":url}];
        }
        [wire addObject:@{@"role":@"user", @"content":content}];
    }
    return wire;
}
