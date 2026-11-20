#import "NSConfig.h"
#import <CoreFoundation/CoreFoundation.h>
#import <notify.h>

static CFStringRef const kNSDomain = CFSTR("com.neostatus.tweak");
static CFStringRef const kNSChanged = CFSTR("com.neostatus.tweak/preferences.changed");

@implementation NSConfig
+ (NSString *)domain { return @"com.neostatus.tweak"; }
+ (NSString *)changedNotification { return @"com.neostatus.tweak/preferences.changed"; }
+ (id)objectForKey:(NSString *)key {
    if (key.length == 0) return nil;
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key, kNSDomain);
    return CFBridgingRelease(value);
}
+ (BOOL)boolForKey:(NSString *)key defaultValue:(BOOL)fallback {
    id value = [self objectForKey:key];
    return value ? [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : fallback : fallback;
}
+ (void)setObject:(id)value forKey:(NSString *)key {
    if (key.length == 0) return;
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, kNSDomain);
    CFPreferencesAppSynchronize(kNSDomain);
    notify_post([(__bridge NSString *)kNSChanged UTF8String]);
}
+ (void)resetAll {
    CFPreferencesSetAppValue(CFSTR("Enabled"), kCFBooleanTrue, kNSDomain);
    CFPreferencesSetAppValue(CFSTR("PreviewGestureEnabled"), kCFBooleanFalse, kNSDomain);
    CFPreferencesSetAppValue(CFSTR("DiagnosticsEnabled"), kCFBooleanTrue, kNSDomain);
    CFPreferencesSetAppValue(CFSTR("GlassEnabled"), kCFBooleanTrue, kNSDomain);
    CFPreferencesSetAppValue(CFSTR("RoundedModulesEnabled"), kCFBooleanTrue, kNSDomain);
    CFPreferencesSetAppValue(CFSTR("ColoredGlyphsEnabled"), kCFBooleanTrue, kNSDomain);
    CFPreferencesSetAppValue(CFSTR("MediaStyleEnabled"), kCFBooleanTrue, kNSDomain);
    NSArray *defaultLayout = @[@"wifi", @"cellular", @"bluetooth", @"airplane", @"hotspot", @"orientation", @"vpn", @"silent", @"focus", @"record", @"flashlight", @"screenmirror"];
    CFPreferencesSetAppValue(CFSTR("NeoStatus.ControlLayout.v2"), (__bridge CFPropertyListRef)defaultLayout, kNSDomain);
    CFPreferencesAppSynchronize(kNSDomain);
    notify_post([(__bridge NSString *)kNSChanged UTF8String]);
}
@end
