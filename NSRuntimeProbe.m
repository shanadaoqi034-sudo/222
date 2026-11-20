#import "NSRuntimeProbe.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <sys/utsname.h>
#import <sys/stat.h>
#import <sys/sysctl.h>
#import <unistd.h>

// Keep all user-shareable diagnostics together. Do not collect serial numbers,
// Apple IDs, installed-app lists, network identifiers, or personal content.
static NSString * const NSPreferredLogDirectory = @"/var/mobile/Library/Logs/NeoStatus";
static const NSUInteger NSMaxSnapshots = 10;
static const NSUInteger NSMaxMethodsPerClass = 180;

@implementation NSRuntimeProbe

+ (NSString *)diagnosticDirectoryPath {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSMutableArray<NSString *> *candidates = [NSMutableArray array];
    [candidates addObject:NSPreferredLogDirectory];
    NSString *home = NSHomeDirectory();
    if (home.length) [candidates addObject:[[home stringByAppendingPathComponent:@"Library/Logs"] stringByAppendingPathComponent:@"NeoStatus"]];
    [candidates addObject:@"/tmp/NeoStatus-Logs"];

    for (NSString *path in candidates) {
        NSError *error = nil;
        NSDictionary *attributes = @{ NSFilePosixPermissions: @0700 };
        [fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:attributes error:&error];
        if (error) {
            NSLog(@"[NeoStatus][DIAG] Cannot create directory %@: %@", path, error);
            continue;
        }
        NSString *probe = [path stringByAppendingPathComponent:@".write-test"];
        NSError *writeError = nil;
        if ([ @"NeoStatus diagnostic write test" writeToFile:probe atomically:YES encoding:NSUTF8StringEncoding error:&writeError]) {
            [fm removeItemAtPath:probe error:nil];
            NSLog(@"[NeoStatus][DIAG] Using writable log directory: %@", path);
            return path;
        }
        NSLog(@"[NeoStatus][DIAG] Directory is not writable %@: %@", path, writeError);
    }
    NSLog(@"[NeoStatus][DIAG][ERROR] No writable diagnostic directory found");
    return @"/tmp";
}

+ (void)writeSpringBoardRuntimeReport {
    [self writeSpringBoardRuntimeReportForReason:@"manual-or-default"];
}

+ (NSString *)safeString:(NSString *)value {
    return value.length ? value : @"(unavailable)";
}

+ (NSString *)fileSystemStatusForPath:(NSString *)path {
    struct stat st;
    if (stat(path.fileSystemRepresentation, &st) != 0) return @"absent";
    NSString *kind = S_ISDIR(st.st_mode) ? @"directory" : (S_ISREG(st.st_mode) ? @"file" : @"other");
    return [NSString stringWithFormat:@"%@ mode=%04o uid=%d gid=%d", kind, st.st_mode & 07777, st.st_uid, st.st_gid];
}

+ (void)appendMethodsForClass:(Class)cls to:(NSMutableString *)out {
    NSString *className = NSStringFromClass(cls);
    [out appendFormat:@"\n[%@ | instance methods]\n", className];
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    unsigned int limit = MIN(count, (unsigned int)NSMaxMethodsPerClass);
    for (unsigned int i = 0; i < limit; i++) {
        SEL selector = method_getName(methods[i]);
        const char *types = method_getTypeEncoding(methods[i]);
        [out appendFormat:@"- %@ | types=%s\n", NSStringFromSelector(selector), types ?: "?"];
    }
    if (count > limit) [out appendFormat:@"... %u methods omitted\n", count - limit];
    free(methods);

    [out appendFormat:@"[%@ | class methods]\n", className];
    count = 0;
    methods = class_copyMethodList(object_getClass(cls), &count);
    limit = MIN(count, 100u);
    for (unsigned int i = 0; i < limit; i++) {
        SEL selector = method_getName(methods[i]);
        const char *types = method_getTypeEncoding(methods[i]);
        [out appendFormat:@"+ %@ | types=%s\n", NSStringFromSelector(selector), types ?: "?"];
    }
    if (count > limit) [out appendFormat:@"... %u class methods omitted\n", count - limit];
    free(methods);
}

+ (void)writeSpringBoardRuntimeReportForReason:(NSString *)reason {
    // UIKit state is captured on the main queue; filesystem and runtime inventory work runs off-main.
    dispatch_async(dispatch_get_main_queue(), ^{
        CGRect capturedBounds = UIScreen.mainScreen.bounds;
        CGFloat capturedScale = UIScreen.mainScreen.scale;
        NSInteger capturedOrientation = (NSInteger)UIApplication.sharedApplication.statusBarOrientation;
        NSString *capturedSystemVersion = UIDevice.currentDevice.systemVersion ?: @"unknown";
        NSString *capturedDeviceModel = UIDevice.currentDevice.model ?: @"unknown";
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        @autoreleasepool {
            NSFileManager *fm = NSFileManager.defaultManager;
            NSString *directory = [self diagnosticDirectoryPath];
            NSDateFormatter *formatter = [NSDateFormatter new];
            formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
            formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
            formatter.dateFormat = @"yyyyMMdd-HHmmss-SSS'Z'";
            NSString *stamp = [formatter stringFromDate:NSDate.date];
            NSString *snapshotName = [NSString stringWithFormat:@"snapshot-%@", stamp];
            NSString *snapshotDirectory = [directory stringByAppendingPathComponent:snapshotName];
            NSError *snapshotError = nil;
            [fm createDirectoryAtPath:snapshotDirectory withIntermediateDirectories:YES attributes:@{ NSFilePosixPermissions: @0700 } error:&snapshotError];
            if (snapshotError) {
                NSLog(@"[NeoStatus][DIAG][ERROR] Cannot create snapshot %@: %@", snapshotDirectory, snapshotError);
                return;
            }

            struct utsname systemInfo;
            uname(&systemInfo);
            CGRect bounds = capturedBounds;
            NSString *machine = [NSString stringWithUTF8String:systemInfo.machine] ?: @"unknown";
            char osBuildBuffer[256] = {0};
            size_t osBuildSize = sizeof(osBuildBuffer);
            NSString *osBuild = (sysctlbyname("kern.osversion", osBuildBuffer, &osBuildSize, NULL, 0) == 0)
                ? ([NSString stringWithUTF8String:osBuildBuffer] ?: @"unknown") : @"unavailable";
            NSString *process = NSProcessInfo.processInfo.processName ?: @"unknown";
            NSString *bundleID = NSBundle.mainBundle.bundleIdentifier ?: @"unknown";
            NSMutableString *summary = [NSMutableString string];
            [summary appendFormat:@"NeoStatus diagnostic snapshot\nTimestamp UTC: %@\nReason: %@\n", stamp, reason ?: @"unspecified"];
            [summary appendFormat:@"Process: %@ (pid=%d)\nBundle: %@\n", process, getpid(), bundleID];
            [summary appendFormat:@"iOS: %@ | build: %@\nDevice model: %@ | hardware: %@\n", capturedSystemVersion, osBuild, capturedDeviceModel, machine];
            [summary appendFormat:@"Screen points: %.0fx%.0f | scale: %.2f | orientation: %ld\n", bounds.size.width, bounds.size.height, capturedScale, (long)capturedOrientation];
            [summary appendFormat:@"Architecture: %@\n", sizeof(void *) == 8 ? @"64-bit" : @"32-bit"];
            [summary appendFormat:@"NSHomeDirectory: %@\n", NSHomeDirectory()];
            [summary appendFormat:@"Diagnostic directory: %@\n", directory];
            [summary appendFormat:@"Reason note: open the stock Control Center during the first minute after respring; timed snapshots are captured below.\n"];

            NSArray<NSString *> *pathChecks = @[
                @"/var/jb", @"/var/jb/basebin", @"/var/jb/usr/lib/TweakInject",
                @"/var/jb/Library/MobileSubstrate/DynamicLibraries",
                @"/var/containers/Bundle/tweaksupport", @"/usr/lib/TweakInject",
                @"/Library/MobileSubstrate/DynamicLibraries",
                @"/var/mobile/Library/Preferences", @"/var/mobile/Library/Logs"
            ];
            NSMutableString *environment = [NSMutableString string];
            [environment appendString:@"Jailbreak / injection environment markers (existence only; no assumptions):\n"];
            for (NSString *path in pathChecks) [environment appendFormat:@"%@ : %@\n", path, [self fileSystemStatusForPath:path]];
            [environment appendString:@"\nLoaded relevant dynamic images:\n"];
            uint32_t imageCount = _dyld_image_count();
            NSUInteger matchedImages = 0;
            for (uint32_t i = 0; i < imageCount; i++) {
                const char *raw = _dyld_get_image_name(i);
                if (!raw) continue;
                NSString *imagePath = [NSString stringWithUTF8String:raw];
                NSString *lower = imagePath.lowercaseString;
                if ([lower containsString:@"ellekit"] || [lower containsString:@"substrate"] ||
                    [lower containsString:@"substitute"] || [lower containsString:@"roothide"] ||
                    [lower containsString:@"relaxin"] || [lower containsString:@"tweak"] ||
                    [lower containsString:@"neostatus"]) {
                    [environment appendFormat:@"%@\n", imagePath];
                    matchedImages++;
                }
            }
            if (!matchedImages) [environment appendString:@"(no matching image names found in this process)\n"];

            NSMutableArray<NSString *> *allMatches = [NSMutableArray array];
            int capacity = objc_getClassList(NULL, 0);
            Class *classes = NULL;
            int actual = 0;
            if (capacity > 0 && capacity < 60000) {
                classes = (__unsafe_unretained Class *)calloc((size_t)capacity, sizeof(Class));
                if (classes) actual = objc_getClassList(classes, capacity);
            }
            NSArray<NSString *> *prefixes = @[@"SBControlCenter", @"CCUI", @"_UIStatusBar", @"UIStatusBar", @"SBUIProudLockIconView"];
            for (int i = 0; i < actual; i++) {
                NSString *name = NSStringFromClass(classes[i]);
                for (NSString *prefix in prefixes) {
                    if ([name hasPrefix:prefix]) { [allMatches addObject:name]; break; }
                }
            }
            [allMatches sortUsingSelector:@selector(compare:)];

            NSMutableString *classReport = [NSMutableString string];
            [classReport appendFormat:@"Runtime class inventory\nTotal classes reported by runtime: %d\nMatched classes: %lu\n\n", actual, (unsigned long)allMatches.count];
            for (NSString *name in allMatches) [classReport appendFormat:@"%@\n", name];

            NSMutableString *methodReport = [NSMutableString string];
            [methodReport appendString:@"Selected runtime method inventory. This is observation only; no private selector is invoked.\n"];
            NSMutableArray<NSString *> *inspectNames = [NSMutableArray arrayWithArray:@[
                @"SBControlCenterController", @"CCUIMainViewController", @"CCUIControlCenterViewController",
                @"UIStatusBarWindow", @"_UIStatusBar", @"UIStatusBar", @"SBStatusBarStateProvider"
            ]];
            for (NSString *name in allMatches) {
                if (([name containsString:@"ControlCenter"] || [name containsString:@"StatusBar"]) &&
                    ![inspectNames containsObject:name] && inspectNames.count < 55) [inspectNames addObject:name];
            }
            for (NSString *name in inspectNames) {
                Class cls = NSClassFromString(name);
                if (cls) [self appendMethodsForClass:cls to:methodReport];
            }
            if (classes) free(classes);

            NSDictionary<NSString *, NSString *> *files = @{
                @"summary.txt": summary,
                @"jailbreak-environment.txt": environment,
                @"control-center-statusbar-classes.txt": classReport,
                @"selected-methods-and-type-encodings.txt": methodReport
            };
            BOOL allFilesWritten = YES;
            for (NSString *name in files) {
                NSString *path = [snapshotDirectory stringByAppendingPathComponent:name];
                NSError *writeError = nil;
                if (![files[name] writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&writeError]) {
                    allFilesWritten = NO;
                    NSLog(@"[NeoStatus][DIAG][ERROR] Failed writing %@: %@", path, writeError);
                } else {
                    [fm setAttributes:@{ NSFilePosixPermissions: @0600 } ofItemAtPath:path error:nil];
                    NSLog(@"[NeoStatus][DIAG] Wrote %@ (%lu bytes)", path, (unsigned long)[files[name] lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
                }
            }
            NSString *latest = [directory stringByAppendingPathComponent:@"LATEST.txt"];
            NSString *latestText = [NSString stringWithFormat:@"Latest snapshot: %@\nReason: %@\nFiles written: %@\n", snapshotDirectory, reason ?: @"unspecified", allFilesWritten ? @"yes" : @"partial"];
            NSError *latestError = nil;
            if (![latestText writeToFile:latest atomically:YES encoding:NSUTF8StringEncoding error:&latestError]) {
                NSLog(@"[NeoStatus][DIAG][ERROR] Failed writing LATEST.txt %@: %@", latest, latestError);
            } else {
                [fm setAttributes:@{ NSFilePosixPermissions: @0600 } ofItemAtPath:latest error:nil];
            }

            // Retain only the newest bounded set of snapshots.
            NSArray<NSString *> *contents = [fm contentsOfDirectoryAtPath:directory error:nil] ?: @[];
            NSMutableArray<NSString *> *snapshots = [NSMutableArray array];
            for (NSString *item in contents) if ([item hasPrefix:@"snapshot-"]) [snapshots addObject:item];
            [snapshots sortUsingSelector:@selector(compare:)];
            while (snapshots.count > NSMaxSnapshots) {
                NSString *oldest = snapshots.firstObject;
                [fm removeItemAtPath:[directory stringByAppendingPathComponent:oldest] error:nil];
                [snapshots removeObjectAtIndex:0];
            }
            NSLog(@"[NeoStatus] Diagnostic snapshot written: %@", snapshotDirectory);
        }
        });
    });
}
@end
