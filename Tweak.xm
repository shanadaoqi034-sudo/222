#import <UIKit/UIKit.h>
#import "NSControlCenterViewController.h"
#import "NSRuntimeProbe.h"
#import "NSConfig.h"
#import <notify.h>

@interface NSPreviewGestureTarget : NSObject
- (void)handleTripleTap:(UITapGestureRecognizer *)gesture;
@end

static NSPreviewGestureTarget *NSGestureTarget;
static __weak UIWindow *NSGestureWindow;
static UITapGestureRecognizer *NSPreviewTap;
static BOOL NSObserversInstalled = NO;

static void NSShowPrototype(void) {
    if (![NSConfig boolForKey:@"Enabled" defaultValue:YES]) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIApplication *app = UIApplication.sharedApplication;
        UIWindowScene *scene = nil;
        for (UIScene *candidate in app.connectedScenes) {
            if ([candidate isKindOfClass:UIWindowScene.class] && candidate.activationState == UISceneActivationStateForegroundActive) { scene=(UIWindowScene *)candidate; break; }
        }
        if (!scene) return;
        UIWindow *keyWindow = nil;
        for (UIWindow *window in scene.windows) if (window.isKeyWindow) { keyWindow = window; break; }
        UIViewController *presenter = keyWindow.rootViewController;
        while (presenter.presentedViewController && !presenter.presentedViewController.isBeingDismissed) presenter = presenter.presentedViewController;
        if (!presenter || [presenter isKindOfClass:NSControlCenterViewController.class]) return;
        NSControlCenterViewController *panel = [NSControlCenterViewController new];
        panel.modalPresentationStyle = UIModalPresentationOverFullScreen;
        panel.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
        [presenter presentViewController:panel animated:YES completion:nil];
    });
}

static void NSRemovePreviewGesture(void) {
    if (!NSGestureWindow || !NSGestureTarget) return;
    if (NSPreviewTap) [NSGestureWindow removeGestureRecognizer:NSPreviewTap];
    NSPreviewTap = nil;
    NSGestureWindow = nil;
    NSGestureTarget = nil;
}

static void NSRefreshPreviewGesture(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSRemovePreviewGesture();
        if (![NSConfig boolForKey:@"Enabled" defaultValue:YES] || ![NSConfig boolForKey:@"PreviewGestureEnabled" defaultValue:NO]) return;
        UIWindow *targetWindow = nil;
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class] || scene.activationState != UISceneActivationStateForegroundActive) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) if (window.isKeyWindow) { targetWindow = window; break; }
            if (targetWindow) break;
        }
        if (!targetWindow) return;
        NSGestureTarget = [NSPreviewGestureTarget new];
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:NSGestureTarget action:@selector(handleTripleTap:)];
        tap.numberOfTapsRequired = 3;
        tap.cancelsTouchesInView = NO;
        [targetWindow addGestureRecognizer:tap];
        NSPreviewTap = tap;
        NSGestureWindow = targetWindow;
    });
}

@implementation NSPreviewGestureTarget
- (void)handleTripleTap:(UITapGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateRecognized) return;
    if ([NSConfig boolForKey:@"DiagnosticsEnabled" defaultValue:YES]) [NSRuntimeProbe writeSpringBoardRuntimeReportForReason:@"user-triple-tap-preview-entry"];
    NSShowPrototype();
}
@end

%group NeoStatusSpringBoard
%hook SpringBoard
- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    if ([NSConfig boolForKey:@"DiagnosticsEnabled" defaultValue:YES]) [NSRuntimeProbe writeSpringBoardRuntimeReportForReason:@"springboard-launch"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ NSRefreshPreviewGesture(); });
    NSArray<NSNumber *> *snapshotDelays = @[@10, @25, @40, @55];
    for (NSNumber *delay in snapshotDelays) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (![NSConfig boolForKey:@"DiagnosticsEnabled" defaultValue:YES]) return;
            NSString *reason = [NSString stringWithFormat:@"post-respring-%@-seconds", delay];
            [NSRuntimeProbe writeSpringBoardRuntimeReportForReason:reason];
        });
    }
}
%end
%end

static void NSInstallNotifications(void) {
    if (NSObserversInstalled) return;
    NSObserversInstalled = YES;
    int token = 0;
    notify_register_dispatch("com.neostatus.tweak/preferences.changed", &token, dispatch_get_main_queue(), ^(int t) {
        NSRefreshPreviewGesture();
    });
    int diagnosticToken = 0;
    notify_register_dispatch("com.neostatus.tweak/diagnostics.request", &diagnosticToken, dispatch_get_main_queue(), ^(int t) {
        if ([NSConfig boolForKey:@"DiagnosticsEnabled" defaultValue:YES]) [NSRuntimeProbe writeSpringBoardRuntimeReportForReason:@"preferences-request"];
    });
}

%ctor {
    @autoreleasepool {
        if ([NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) {
            NSInstallNotifications();
            if ([NSConfig boolForKey:@"DiagnosticsEnabled" defaultValue:YES]) [NSRuntimeProbe writeSpringBoardRuntimeReportForReason:@"tweak-constructor-loaded"];
            %init(NeoStatusSpringBoard);
        }
    }
}
