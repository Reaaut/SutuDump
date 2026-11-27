#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>

static NSMutableSet<NSString *> *gSeen = nil;
static NSMutableArray<NSString *> *gPwds = nil;
static NSString *gRoot = nil;
static dispatch_queue_t gQ = nil;
static __thread BOOL tBusy = NO;
static __thread NSString *tCurPath = nil;   // 当前正在打开的归档路径

static NSString *INNER_PW = @"2E@Qws#b9MQ6p4^sRS";

static NSString *pickRoot(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSMutableArray *cands = [NSMutableArray array];

    NSString *home = NSHomeDirectory();
    if (home.length) {
        [cands addObject:[home stringByAppendingPathComponent:@"Documents/sutu_dump"]];
        [cands addObject:[home stringByAppendingPathComponent:@"Library/sutu_dump"]];
        [cands addObject:[home stringByAppendingPathComponent:@"tmp/sutu_dump"]];
    }
    [cands addObject:@"/var/mobile/Documents/sutu_dump"];
    [cands addObject:@"/var/jb/var/mobile/Documents/sutu_dump"];
    [cands addObject:@"/var/tmp/sutu_dump"];

    for (NSString *c in cands) {
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:c isDirectory:&isDir] && isDir) return c;
        NSError *e = nil;
        if ([fm createDirectoryAtPath:c withIntermediateDirectories:YES attributes:nil error:&e]) return c;
    }
    return NSTemporaryDirectory();
}

static void ensureInit(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gSeen = [NSMutableSet new];
        gPwds = [NSMutableArray new];
        gQ = dispatch_queue_create("com.yg.sutudump", DISPATCH_QUEUE_SERIAL);
        gRoot = pickRoot();
        NSFileManager *fm = NSFileManager.defaultManager;
        for (NSString *sub in @[@"out", @"raw"]) {
            [fm createDirectoryAtPath:[gRoot stringByAppendingPathComponent:sub]
          withIntermediateDirectories:YES attributes:nil error:nil];
        }
        NSLog(@"[SUTU] v3 root=%@", gRoot);
    });
}

static void appendLine(NSString *file, NSString *line) {
    ensureInit();
    NSString *p = [gRoot stringByAppendingPathComponent:file];
    FILE *fp = fopen(p.UTF8String, "a");
    if (fp) {
        fwrite(line.UTF8String, 1, strlen(line.UTF8String), fp);
        fclose(fp);
    }
}

static BOOL isInner(NSString *pwd) {
    return [pwd isEqualToString:INNER_PW];
}

// 输出：密码 \t 文件路径 \t 类型
static void logPwd(NSString *pwd, NSString *src, NSString *path) {
    if (!pwd || pwd.length < 6) return;
    ensureInit();

    NSString *key = [NSString stringWithFormat:@"%@|%@", pwd, path ?: @"-"];
    @synchronized (gSeen) {
        if ([gSeen containsObject:key]) return;
        [gSeen addObject:key];
        if (![gPwds containsObject:pwd]) [gPwds addObject:pwd];
    }

    BOOL inner = isInner(pwd);
    NSString *kind = inner ? @"inner" : @"outer";
    NSString *shortPath = path.lastPathComponent ?: @"-";

    NSString *line = [NSString stringWithFormat:@"%@\t%@\t%@\t%@\n",
                      pwd, shortPath, kind, src];
    appendLine(inner ? @"inner.txt" : @"outer.txt", line);
    // 同时写一份配对总表，方便脚本直接读
    appendLine(@"pairs.txt", line);
    NSLog(@"[SUTU] %@ pwd=%@ file=%@", kind, pwd, shortPath);

    // 外层密码：把完整路径也记下来
    if (!inner && path.length) {
        appendLine(@"outer_paths.txt",
                   [NSString stringWithFormat:@"%@\t%@\n", pwd, path]);
    }
}

static BOOL isZip(NSData *d) {
    if (d.length < 4) return NO;
    const uint8_t *b = (const uint8_t *)d.bytes;
    return b[0] == 'P' && b[1] == 'K';
}

static NSString *safeName(NSString *s) {
    NSCharacterSet *bad = [NSCharacterSet characterSetWithCharactersInString:@"/\\:*?\"<>|"];
    return [[s componentsSeparatedByCharactersInSet:bad] componentsJoinedByString:@"_"];
}

static NSArray *openEntries(id archive, NSString *pwd, NSError **err) {
    tBusy = YES;
    NSArray *e = nil;
    SEL sNew = NSSelectorFromString(@"newEntriesWithPassword:error:");
    SEL sOld = NSSelectorFromString(@"entriesWithPassword:error:");
    if ([archive respondsToSelector:sNew]) {
        e = ((id (*)(id, SEL, NSString *, NSError **))objc_msgSend)(archive, sNew, pwd, err);
    } else if ([archive respondsToSelector:sOld]) {
        e = ((id (*)(id, SEL, NSString *, NSError **))objc_msgSend)(archive, sOld, pwd, err);
    }
    tBusy = NO;
    return e;
}

static NSData *entryData(id entry, NSString *pwd) {
    SEL s = NSSelectorFromString(@"newDataWithPassword:error:");
    if (![entry respondsToSelector:s]) return nil;
    tBusy = YES;
    NSData *d = ((id (*)(id, SEL, NSString *, NSError **))objc_msgSend)(entry, s, pwd, NULL);
    tBusy = NO;
    return d;
}

static id openArchive(NSURL *url) {
    Class ZA = NSClassFromString(@"ZZArchive");
    if (!ZA) return nil;
    SEL s = NSSelectorFromString(@"archiveWithURL:error:");
    if ([ZA respondsToSelector:s]) {
        return ((id (*)(id, SEL, NSURL *, NSError **))objc_msgSend)(ZA, s, url, NULL);
    }
    return nil;
}

static void unpackData(NSData *data, NSString *hint, NSString *outDir, int depth) {
    if (depth > 4 || !isZip(data)) return;
    ensureInit();
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:
                     [NSString stringWithFormat:@"sd_%d_%u.zip", depth, arc4random()]];
    if (![data writeToFile:tmp atomically:YES]) return;

    if (!NSClassFromString(@"ZZArchive")) { [fm removeItemAtPath:tmp error:nil]; return; }
    id archive = openArchive([NSURL fileURLWithPath:tmp]);
    if (!archive) { [fm removeItemAtPath:tmp error:nil]; return; }

    NSMutableArray *cands = [NSMutableArray array];
    if (hint.length) [cands addObject:hint];
    @synchronized (gPwds) { [cands addObjectsFromArray:gPwds]; }
    if (![cands containsObject:INNER_PW]) [cands addObject:INNER_PW];

    NSArray *entries = nil;
    NSString *used = nil;
    for (NSString *p in cands) {
        NSError *e2 = nil;
        NSArray *r = openEntries(archive, p, &e2);
        if (r.count) { entries = r; used = p; break; }
    }
    if (!entries.count) { [fm removeItemAtPath:tmp error:nil]; return; }

    [fm createDirectoryAtPath:outDir withIntermediateDirectories:YES attributes:nil error:nil];
    for (id entry in entries) {
        NSString *name = nil;
        @try { name = [entry valueForKey:@"fileName"]; } @catch (__unused NSException *ex) {}
        if (![name isKindOfClass:NSString.class] || !name.length) continue;
        NSData *d = entryData(entry, used);
        if (!d.length) continue;
        NSString *safe = safeName(name);
        if (isZip(d)) {
            unpackData(d, nil, [outDir stringByAppendingPathComponent:
                                [safe.stringByDeletingPathExtension stringByAppendingString:@"_x"]],
                       depth + 1);
        } else {
            [d writeToFile:[outDir stringByAppendingPathComponent:safe] atomically:YES];
        }
    }
    [fm removeItemAtPath:tmp error:nil];
}

__attribute__((constructor)) static void sutudump_init(void) {
    ensureInit();
    NSLog(@"[SUTU] v3 loaded root=%@", gRoot);
}

#pragma mark - 记录“正在打开哪个包”

%hook ZZArchive
+ (id)archiveWithURL:(NSURL *)url error:(NSError **)err {
    tCurPath = url.path;
    return %orig;
}
- (id)initWithURL:(NSURL *)url options:(id)opts error:(NSError **)err {
    tCurPath = url.path;
    return %orig;
}
%end

#pragma mark - 密码抓取（带文件路径）

%hook ZZOldArchiveEntry
- (NSData *)newDataWithPassword:(NSString *)pwd error:(NSError **)err {
    NSData *d = %orig;
    if (!tBusy && pwd.length > 0) {
        NSString *path = tCurPath;
        logPwd(pwd, @"ZZOld", path);
        if (isZip(d)) {
            NSData *copy = [d copy];
            NSString *p = [pwd copy];
            NSString *tag = [path.lastPathComponent.stringByDeletingPathExtension copy] ?: @"pkg";
            dispatch_async(gQ, ^{
                NSString *dir = [gRoot stringByAppendingPathComponent:
                                 [NSString stringWithFormat:@"out/%@", safeName(tag)]];
                unpackData(copy, p, dir, 0);
            });
        }
    }
    return d;
}
%end

%hook ZZNewArchiveEntry
- (NSData *)newDataWithPassword:(NSString *)pwd error:(NSError **)err {
    NSData *d = %orig;
    if (!tBusy && pwd.length > 0) logPwd(pwd, @"ZZNew", tCurPath);
    return d;
}
%end

#pragma mark - 接口响应里的密码（不用下载也能抓）

%hook NSJSONSerialization
+ (id)JSONObjectWithData:(NSData *)data options:(NSJSONReadingOptions)opt error:(NSError **)err {
    id obj = %orig;
    if (!tBusy && obj && ![obj isKindOfClass:NSNull.class]) {
        NSString *s = nil;
        @try { s = [obj description]; } @catch (__unused NSException *e) {}
        if (s.length > 20) {
            static NSRegularExpression *re = nil;
            static dispatch_once_t once;
            dispatch_once(&once, ^{
                re = [NSRegularExpression regularExpressionWithPattern:
                      @"[A-Za-z0-9\\^\\$\\._!@#%&\\*\\(\\)\\-]{18,64}"
                                                             options:0 error:nil];
            });
            [re enumerateMatchesInString:s options:0 range:NSMakeRange(0, s.length)
                              usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags f, BOOL *stop) {
                NSString *cand = [s substringWithRange:m.range];
                BOOL hasDigit = [cand rangeOfCharacterFromSet:[NSCharacterSet decimalDigitCharacterSet]].location != NSNotFound;
                BOOL hasAlpha = [cand rangeOfCharacterFromSet:[NSCharacterSet letterCharacterSet]].location != NSNotFound;
                if (hasDigit && hasAlpha) logPwd(cand, @"JSON", @"(api)");
            }];
        }
    }
    return obj;
}
%end
