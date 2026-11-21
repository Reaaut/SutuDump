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

static NSString *pickRoot(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSMutableArray *cands = [NSMutableArray array];

    // 1) 宿主 App 自己的沙盒（注入微信就落到微信主路径）
    NSString *home = NSHomeDirectory();
    if (home.length) {
        [cands addObject:[home stringByAppendingPathComponent:@"Documents/sutu_dump"]];
        [cands addObject:[home stringByAppendingPathComponent:@"Library/sutu_dump"]];
        [cands addObject:[home stringByAppendingPathComponent:@"tmp/sutu_dump"]];
    }
    // 2) 全局可写位置做兜底
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
        for (NSString *sub in @[@"out", @"inbox", @"raw"]) {
            [fm createDirectoryAtPath:[gRoot stringByAppendingPathComponent:sub]
          withIntermediateDirectories:YES attributes:nil error:nil];
        }
        NSLog(@"[SUTU] root=%@", gRoot);
    });
}

static void appendLine(NSString *file, NSString *line) {
    ensureInit();
    NSString *p = [gRoot stringByAppendingPathComponent:file];
    FILE *fp = fopen(p.UTF8String, "a");
    if (fp) { fwrite(line.UTF8String, 1, strlen(line.UTF8String), fp); fclose(fp); }
}

static void logPwd(NSString *pwd, NSString *src) {
    if (!pwd || pwd.length < 6) return;
    ensureInit();
    @synchronized (gSeen) {
        if ([gSeen containsObject:pwd]) return;
        [gSeen addObject:pwd];
        [gPwds addObject:pwd];
    }
    appendLine(@"pwd.txt", [NSString stringWithFormat:@"%@\t%@\n", pwd, src]);
    NSLog(@"[SUTU] PWD %@ (%@)", pwd, src);
}

static BOOL isZip(NSData *d) {
    if (d.length < 4) return NO;
    const uint8_t *b = (const uint8_t *)d.bytes;
    return b[0] == 'P' && b[1] == 'K';
}

static NSString *safeName(NSString *s) {
    NSCharacterSet *bad = [NSCharacterSet characterSetWithCharactersInString:@"/\\:*?\"<>|"];
    NSArray *parts = [s componentsSeparatedByCharactersInSet:bad];
    return [parts componentsJoinedByString:@"_"];
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
    Class ZZArchive = NSClassFromString(@"ZZArchive");
    if (!ZZArchive) return nil;
    SEL s = NSSelectorFromString(@"archiveWithURL:error:");
    if (![ZZArchive respondsToSelector:s]) {
        s = NSSelectorFromString(@"archiveWithURL:options:error:");
        if (![ZZArchive respondsToSelector:s]) return nil;
        return ((id (*)(id, SEL, NSURL *, id, NSError **))objc_msgSend)(ZZArchive, s, url, nil, NULL);
    }
    return ((id (*)(id, SEL, NSURL *, NSError **))objc_msgSend)(ZZArchive, s, url, NULL);
}

static void unpackData(NSData *data, NSString *hint, NSString *outDir, int depth) {
    if (depth > 4 || !isZip(data)) return;
    ensureInit();
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:
                     [NSString stringWithFormat:@"sd_%d_%u.zip", depth, arc4random()]];
    if (![data writeToFile:tmp atomically:YES]) return;

    Class ZZArchive = NSClassFromString(@"ZZArchive");
    if (!ZZArchive) { [fm removeItemAtPath:tmp error:nil]; return; }

    id archive = openArchive([NSURL fileURLWithPath:tmp]);
    if (!archive) { [fm removeItemAtPath:tmp error:nil]; return; }

    NSMutableArray *cands = [NSMutableArray array];
    if (hint.length) [cands addObject:hint];
    @synchronized (gPwds) { [cands addObjectsFromArray:gPwds]; }
    if (![cands containsObject:@"2E@Qws#b9MQ6p4^sRS"]) [cands addObject:@"2E@Qws#b9MQ6p4^sRS"];

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
        if (isZip(d)) {
            NSString *sub = [outDir stringByAppendingPathComponent:
                             [safeName(name.lastPathComponent.stringByDeletingPathExtension) stringByAppendingString:@"_x"]];
            unpackData(d, nil, sub, depth + 1);
        } else {
            [d writeToFile:[outDir stringByAppendingPathComponent:safeName(name)] atomically:YES];
        }
    }
    [fm removeItemAtPath:tmp error:nil];
    NSLog(@"[SUTU] unpacked %lu entries -> %@ (depth %d)", (unsigned long)entries.count, outDir, depth);
}

__attribute__((constructor)) static void sutudump_init(void) {
    ensureInit();
    NSLog(@"[SUTU] v2 loaded, root=%@", gRoot);
}

%hook ZZOldArchiveEntry
- (NSData *)newDataWithPassword:(NSString *)pwd error:(NSError **)err {
    NSData *d = %orig;
    if (!tBusy && pwd.length) {
        logPwd(pwd, @"ZZOld");
        if (isZip(d)) {
            NSData *copy = [d copy];
            NSString *p = [pwd copy];
            dispatch_async(gQ, ^{
                if (![copy writeToFile:[gRoot stringByAppendingPathComponent:
                                        [NSString stringWithFormat:@"raw/%@.rbt", [p substringToIndex:MIN((NSUInteger)6, p.length)]]]
                            atomically:YES]) {}
                NSString *dir = [gRoot stringByAppendingPathComponent:
                                 [NSString stringWithFormat:@"out/%@", [p substringToIndex:MIN((NSUInteger)6, p.length)]]];
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
    if (!tBusy && pwd.length) logPwd(pwd, @"ZZNew");
    return d;
}
%end

%hook NSUserDefaults
- (id)objectForKey:(NSString *)key {
    id v = %orig;
    if ([key isEqualToString:@"ThemeCurentAssetFloderNameKey"] && [v isKindOfClass:NSString.class]) {
        NSString *s = (NSString *)v;
        if (s.length) {
            appendLine(@"theme_folder.txt", [s stringByAppendingString:@"\n"]);
            NSLog(@"[SUTU] themeFolder=%@", s);
        }
    }
    return v;
}
%end

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
                if (hasDigit && hasAlpha) logPwd(cand, @"JSON");
            }];
        }
    }
    return obj;
}
%end
