#import "NSControlCenterViewController.h"
#import "NSGlassPanel.h"
#import "NSConfig.h"
#import "NSControlTile.h"
#import <MediaPlayer/MediaPlayer.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <math.h>

@class NSControlCenterViewController;
static void NSConfigChangedCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo);

static NSString * const NSLayoutDefaultsKey = @"NeoStatus.ControlLayout.v2";

@interface NSControlCenterViewController () <UIScrollViewDelegate>
@property(nonatomic,strong) UIVisualEffectView *backdrop;
@property(nonatomic,strong) UIScrollView *pages;
@property(nonatomic,strong) UIPageControl *pageControl;
@property(nonatomic,strong) UILabel *clockLabel;
@property(nonatomic,strong) UILabel *statusLabel;
@property(nonatomic,strong) UIButton *editButton;
@property(nonatomic,strong) UIView *mainPage;
@property(nonatomic,strong) UIView *connectivityPage;
@property(nonatomic,strong) NSMutableArray<NSString *> *controlIDs;
@property(nonatomic,assign) BOOL editingControls;
@property(nonatomic,strong) MPVolumeView *volumeView;
@property(nonatomic,strong) UISlider *volumeSlider;
@property(nonatomic,strong) UISlider *brightnessSlider;
@property(nonatomic,copy) NSString *draggingControlID;
@property(nonatomic,assign) NSInteger lastDragIndex;
@property(nonatomic,strong) NSTimer *clockTimer;
- (void)refreshAppearanceFromPreferences;
@end

static void NSConfigChangedCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    NSControlCenterViewController *controller = (__bridge NSControlCenterViewController *)observer;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!controller.isViewLoaded) return;
        // The master switch must take effect immediately, including when the
        // preview is already presented. Never leave an active panel behind.
        if (![NSConfig boolForKey:@"Enabled" defaultValue:YES]) {
            if (controller.presentingViewController && !controller.isBeingDismissed) {
                [controller dismissViewControllerAnimated:NO completion:nil];
            }
            return;
        }
        if (controller.draggingControlID.length) return;
        [controller refreshAppearanceFromPreferences];
    });
}

@implementation NSControlCenterViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.modalPresentationCapturesStatusBarAppearance = YES;
    self.modalPresentationStyle = UIModalPresentationOverFullScreen;
    self.view.backgroundColor = UIColor.clearColor;
    id rawSavedLayout = [NSConfig objectForKey:NSLayoutDefaultsKey];
    NSArray *savedLayout = [rawSavedLayout isKindOfClass:NSArray.class] ? (NSArray *)rawSavedLayout : nil;
    NSSet *allowedIDs = [NSSet setWithArray:@[@"wifi", @"cellular", @"bluetooth", @"airplane", @"hotspot", @"orientation", @"vpn", @"silent", @"focus", @"record", @"flashlight", @"screenmirror"]];
    NSMutableArray *validated = [NSMutableArray array];
    for (id item in savedLayout) if ([item isKindOfClass:NSString.class] && [allowedIDs containsObject:item] && ![validated containsObject:item]) [validated addObject:item];
    self.controlIDs = [validated mutableCopy];
    if (!savedLayout || self.controlIDs.count == 0) {
        self.controlIDs = [@[@"wifi", @"cellular", @"bluetooth", @"airplane", @"hotspot", @"orientation", @"vpn", @"silent", @"focus", @"record", @"flashlight", @"screenmirror"] mutableCopy];
    }

    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
    self.backdrop = [[UIVisualEffectView alloc] initWithEffect:blur];
    self.backdrop.frame = self.view.bounds;
    self.backdrop.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.backdrop];

    UIView *tint = [[UIView alloc] initWithFrame:self.view.bounds];
    tint.backgroundColor = [UIColor colorWithWhite:0.02 alpha:0.28];
    tint.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:tint];

    self.clockLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.clockLabel.text = @"--:--";
    self.clockLabel.textColor = UIColor.whiteColor;
    self.clockLabel.font = [UIFont systemFontOfSize:25 weight:UIFontWeightBold];
    [self.view addSubview:self.clockLabel];

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.statusLabel.text = [self statusSummary];
    self.statusLabel.textColor = [UIColor colorWithWhite:1 alpha:0.7];
    self.statusLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    [self.view addSubview:self.statusLabel];

    self.editButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.editButton setTitle:@"编辑" forState:UIControlStateNormal];
    [self.editButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.editButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    self.editButton.backgroundColor = [UIColor colorWithWhite:1 alpha:0.14];
    self.editButton.layer.cornerRadius = 17;
    [self.editButton addTarget:self action:@selector(toggleEditing) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.editButton];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    [close setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
    close.tintColor = UIColor.whiteColor;
    close.backgroundColor = [UIColor colorWithWhite:1 alpha:0.14];
    close.layer.cornerRadius = 18;
    close.frame = CGRectMake(0, 0, 36, 36);
    [close addTarget:self action:@selector(dismissPanel) forControlEvents:UIControlEventTouchUpInside];
    close.tag = 9001;
    [self.view addSubview:close];

    self.pages = [[UIScrollView alloc] initWithFrame:CGRectZero];
    self.pages.pagingEnabled = YES;
    self.pages.showsHorizontalScrollIndicator = NO;
    self.pages.delegate = self;
    self.pages.clipsToBounds = NO;
    [self.view addSubview:self.pages];

    [self buildMainPage];
    [self buildConnectivityPage];

    self.pageControl = [[UIPageControl alloc] initWithFrame:CGRectZero];
    self.pageControl.numberOfPages = 2;
    self.pageControl.currentPage = 0;
    self.pageControl.currentPageIndicatorTintColor = UIColor.whiteColor;
    self.pageControl.pageIndicatorTintColor = [UIColor colorWithWhite:1 alpha:0.3];
    [self.pageControl addTarget:self action:@selector(pageChanged) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.pageControl];

    [self refreshHeader];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(environmentDidChange:) name:UIDeviceBatteryLevelDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(environmentDidChange:) name:UIDeviceBatteryStateDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(environmentDidChange:) name:NSProcessInfoPowerStateDidChangeNotification object:nil];
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)self,
                                    NSConfigChangedCallback, CFSTR("com.neostatus.tweak/preferences.changed"),
                                    NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    [self layoutForCurrentBounds];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self refreshHeader];
    [self.clockTimer invalidate];
    self.clockTimer = [NSTimer scheduledTimerWithTimeInterval:30.0 target:self selector:@selector(refreshHeader) userInfo:nil repeats:YES];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.clockTimer invalidate];
    self.clockTimer = nil;
}

- (void)dealloc {
    [self.clockTimer invalidate];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)self,
                                       CFSTR("com.neostatus.tweak/preferences.changed"), NULL);
}

- (void)refreshAppearanceFromPreferences {
    BOOL glassEnabled = [NSConfig boolForKey:@"GlassEnabled" defaultValue:YES];
    self.backdrop.effect = glassEnabled
        ? [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark]
        : nil;
    [self layoutMainControls];
    [self layoutConnectivityControls];
    [self refreshHeader];
}

- (void)environmentDidChange:(NSNotification *)notification {
    [self refreshHeader];
}

- (void)refreshHeader {
    NSDateFormatter *timeFormatter = [NSDateFormatter new];
    timeFormatter.locale = [NSLocale currentLocale];
    timeFormatter.dateFormat = @"HH:mm";
    self.clockLabel.text = [timeFormatter stringFromDate:NSDate.date];
    self.statusLabel.text = [self statusSummary];
}

- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleLightContent; }
- (BOOL)prefersStatusBarHidden { return NO; }

- (NSString *)statusSummary {
    UIDevice.currentDevice.batteryMonitoringEnabled = YES;
    float level = UIDevice.currentDevice.batteryLevel;
    NSString *battery = (level >= 0.0f && level <= 1.0f)
        ? [NSString stringWithFormat:@"电池 %.0f%%", level * 100.0f]
        : @"电池状态不可用";
    NSString *power = NSProcessInfo.processInfo.lowPowerModeEnabled ? @"低电量模式" : @"低电量模式关闭";
    return [NSString stringWithFormat:@"%@  ·  %@  ·  预览模式", battery, power];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutForCurrentBounds];
}

- (void)layoutForCurrentBounds {
    CGRect b = self.view.bounds;
    CGFloat top = self.view.safeAreaInsets.top;
    CGFloat bottom = self.view.safeAreaInsets.bottom;
    self.clockLabel.frame = CGRectMake(22, top + 10, CGRectGetWidth(b)-150, 32);
    self.statusLabel.frame = CGRectMake(24, top + 43, CGRectGetWidth(b)-48, 18);
    self.editButton.frame = CGRectMake(CGRectGetWidth(b)-104, top+12, 48, 34);
    UIView *close = [self.view viewWithTag:9001];
    close.frame = CGRectMake(CGRectGetWidth(b)-48, top+11, 36, 36);
    CGFloat contentY = top + 72;
    CGFloat contentH = CGRectGetHeight(b) - contentY - bottom - 42;
    CGRect newPagesFrame = CGRectMake(14, contentY, CGRectGetWidth(b)-28, MAX(220, contentH));
    BOOL pageSizeChanged = !CGRectEqualToRect(self.pages.frame, newPagesFrame);
    self.pages.frame = newPagesFrame;
    self.pageControl.frame = CGRectMake(0, CGRectGetHeight(b)-bottom-30, CGRectGetWidth(b), 20);
    if (pageSizeChanged || self.pages.contentSize.width == 0) [self rebuildPagesForCurrentSize];
}

- (void)rebuildPagesForCurrentSize {
    if (!self.pages || CGRectGetWidth(self.pages.bounds) <= 0) return;
    CGFloat w = CGRectGetWidth(self.pages.bounds), h = CGRectGetHeight(self.pages.bounds);
    self.mainPage.frame = CGRectMake(0, 0, w, h);
    self.connectivityPage.frame = CGRectMake(w, 0, w, h);
    self.pages.contentSize = CGSizeMake(w*2, h);
    [self layoutMainControls];
    [self layoutConnectivityControls];
}

- (NSDictionary *)definitionForID:(NSString *)identifier {
    NSDictionary *map = @{
      @"wifi": @{@"title":@"Wi-Fi", @"subtitle":@"预览控件", @"symbol":@"wifi", @"active":@NO},
      @"cellular": @{@"title":@"蜂窝数据", @"subtitle":@"预览控件", @"symbol":@"antenna.radiowaves.left.and.right", @"active":@NO},
      @"bluetooth": @{@"title":@"蓝牙", @"subtitle":@"预览控件", @"symbol":@"bluetooth", @"active":@NO},
      @"airplane": @{@"title":@"飞行模式", @"subtitle":@"预览控件", @"symbol":@"airplane", @"active":@NO},
      @"hotspot": @{@"title":@"个人热点", @"subtitle":@"预览控件", @"symbol":@"personalhotspot", @"active":@NO},
      @"orientation": @{@"title":@"方向锁定", @"subtitle":@"预览控件", @"symbol":@"lock.rotation", @"active":@NO},
      @"vpn": @{@"title":@"VPN", @"subtitle":@"预览控件", @"symbol":@"network", @"active":@NO},
      @"silent": @{@"title":@"静音模式", @"subtitle":@"预览控件", @"symbol":@"bell.slash.fill", @"active":@NO},
      @"focus": @{@"title":@"专注模式", @"subtitle":@"勿扰模式", @"symbol":@"moon.fill", @"active":@NO},
      @"record": @{@"title":@"录屏", @"subtitle":@"未录制", @"symbol":@"record.circle", @"active":@NO},
      @"flashlight": @{@"title":@"手电筒", @"subtitle":@"关闭", @"symbol":@"flashlight.off.fill", @"active":@NO},
      @"screenmirror": @{@"title":@"屏幕镜像", @"subtitle":@"未连接", @"symbol":@"airplayvideo", @"active":@NO}
    };
    return map[identifier] ?: @{@"title":identifier, @"subtitle":@"", @"symbol":@"circle", @"active":@NO};
}

- (void)buildMainPage {
    CGFloat w = CGRectGetWidth(self.pages.bounds), h = CGRectGetHeight(self.pages.bounds);
    UIScrollView *mainScroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0,0,w,h)];
    mainScroll.showsVerticalScrollIndicator = NO;
    mainScroll.alwaysBounceVertical = YES;
    self.mainPage = mainScroll;
    [self.pages addSubview:self.mainPage];
    [self layoutMainControls];
}

- (void)layoutMainControls {
    if (!self.mainPage) return;
    for (UIView *v in self.mainPage.subviews) [v removeFromSuperview];
    CGFloat w = CGRectGetWidth(self.mainPage.bounds);
    CGFloat gap = 9;
    CGFloat tileW = (w-gap)/2.0;
    CGFloat tileH = MIN(68, MAX(58, (CGRectGetHeight(self.mainPage.bounds)-220)/6.0));
    NSUInteger count = self.controlIDs.count;
    for (NSUInteger i=0; i<count; i++) {
        NSString *identifier = self.controlIDs[i];
        NSDictionary *d = [self definitionForID:identifier];
        NSControlTile *tile = [[NSControlTile alloc] initWithTitle:d[@"title"] subtitle:d[@"subtitle"] symbol:d[@"symbol"] active:[d[@"active"] boolValue]];
        tile.tag = 1000 + (NSInteger)i;
        tile.frame = CGRectMake((i%2)*(tileW+gap), (i/2)*(tileH+gap), tileW, tileH);
        tile.accessibilityIdentifier = identifier;
        [tile addTarget:self action:@selector(controlTileTapped:) forControlEvents:UIControlEventTouchUpInside];
        UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(controlTileHeld:)];
        hold.minimumPressDuration = 0.28;
        [tile addGestureRecognizer:hold];
        if (self.editingControls) {
            tile.alpha = 0.94;
            UIButton *remove = [UIButton buttonWithType:UIButtonTypeSystem];
            remove.frame = CGRectMake(CGRectGetWidth(tile.bounds)-27, 5, 22, 22);
            remove.layer.cornerRadius = 11;
            remove.backgroundColor = [UIColor colorWithRed:0.95 green:0.22 blue:0.24 alpha:0.96];
            [remove setImage:[UIImage systemImageNamed:@"minus"] forState:UIControlStateNormal];
            remove.tintColor = UIColor.whiteColor;
            remove.tag = 2000 + (NSInteger)i;
            [remove addTarget:self action:@selector(removeControlButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
            [tile addSubview:remove];
        }
        [self.mainPage addSubview:tile];
    }
    CGFloat y = ceil(count/2.0)*(tileH+gap)+5;
    CGFloat sliderW = (w-gap)/2.0;
    NSGlassPanel *brightness = [[NSGlassPanel alloc] initWithFrame:CGRectMake(0,y,sliderW,112) cornerRadius:24];
    NSGlassPanel *volume = [[NSGlassPanel alloc] initWithFrame:CGRectMake(sliderW+gap,y,sliderW,112) cornerRadius:24];
    [self.mainPage addSubview:brightness]; [self.mainPage addSubview:volume];
    UILabel *bl = [[UILabel alloc] initWithFrame:CGRectMake(12,8,sliderW-24,18)]; bl.text=@"☀︎  亮度"; bl.textColor=UIColor.whiteColor; bl.font=[UIFont systemFontOfSize:12 weight:UIFontWeightSemibold]; [brightness.contentView addSubview:bl];
    self.brightnessSlider = [[UISlider alloc] initWithFrame:CGRectMake(10,48,sliderW-20,34)];
    self.brightnessSlider.minimumValue=0.05; self.brightnessSlider.maximumValue=1; self.brightnessSlider.value=UIScreen.mainScreen.brightness;
    [self.brightnessSlider addTarget:self action:@selector(brightnessChanged:) forControlEvents:UIControlEventValueChanged];
    [brightness.contentView addSubview:self.brightnessSlider];
    UILabel *vl = [[UILabel alloc] initWithFrame:CGRectMake(12,8,sliderW-24,18)]; vl.text=@"◖))  音量"; vl.textColor=UIColor.whiteColor; vl.font=[UIFont systemFontOfSize:12 weight:UIFontWeightSemibold]; [volume.contentView addSubview:vl];
    self.volumeView = [[MPVolumeView alloc] initWithFrame:CGRectMake(8,45,sliderW-16,36)];
    self.volumeView.showsRouteButton = NO;
    self.volumeView.showsVolumeSlider = YES;
    [volume.contentView addSubview:self.volumeView];
    [self.volumeView sizeToFit];
    UIButton *music = [UIButton buttonWithType:UIButtonTypeSystem];
    music.frame = CGRectMake(0,y+122,w,58);
    BOOL modernMedia = [NSConfig boolForKey:@"MediaStyleEnabled" defaultValue:YES];
    music.backgroundColor = [UIColor colorWithWhite:1 alpha:(modernMedia ? 0.10 : 0.04)];
    music.layer.cornerRadius = modernMedia ? 22 : 10;
    [music setTitle:@"♫     正在播放     播放 / 暂停" forState:UIControlStateNormal];
    [music setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [music addTarget:self action:@selector(togglePlayback) forControlEvents:UIControlEventTouchUpInside];
    [self.mainPage addSubview:music];
    if (self.editingControls) {
        UIButton *add = [UIButton buttonWithType:UIButtonTypeSystem];
        add.frame = CGRectMake(0,y+190,w,48);
        add.backgroundColor = [UIColor colorWithWhite:1 alpha:0.14]; add.layer.cornerRadius=20;
        [add setTitle:@"＋ 添加控制" forState:UIControlStateNormal]; [add setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        [add addTarget:self action:@selector(addControl) forControlEvents:UIControlEventTouchUpInside];
        [self.mainPage addSubview:add];
    }
    if ([self.mainPage isKindOfClass:UIScrollView.class]) {
        CGFloat contentHeight = y + (self.editingControls ? 248 : 190);
        ((UIScrollView *)self.mainPage).contentSize = CGSizeMake(w, MAX(CGRectGetHeight(self.mainPage.bounds), contentHeight));
    }
}

- (void)buildConnectivityPage {
    CGFloat w=CGRectGetWidth(self.pages.bounds), h=CGRectGetHeight(self.pages.bounds);
    self.connectivityPage=[[UIView alloc] initWithFrame:CGRectMake(w,0,w,h)];
    [self.pages addSubview:self.connectivityPage];
    [self layoutConnectivityControls];
}

- (void)layoutConnectivityControls {
    if (!self.connectivityPage) return;
    for (UIView *v in self.connectivityPage.subviews) [v removeFromSuperview];
    CGFloat w=CGRectGetWidth(self.connectivityPage.bounds), gap=10, tileW=(w-gap)/2.0;
    NSControlTile *air=[[NSControlTile alloc] initWithTitle:@"飞行模式" subtitle:@"预览控件" symbol:@"airplane" active:NO];
    air.frame=CGRectMake(0,0,w,62); [self.connectivityPage addSubview:air];
    NSArray *ids=@[@"wifi",@"airdrop",@"cellular",@"bluetooth"];
    NSArray *titles=@[@"Wi-Fi",@"隔空投送",@"蜂窝数据",@"蓝牙"];
    NSArray *symbols=@[@"wifi",@"airplayaudio",@"antenna.radiowaves.left.and.right",@"bluetooth"];
    NSArray *subs=@[@"预览控件",@"仅限联系人",@"预览控件",@"预览控件"];
    for(NSUInteger i=0;i<ids.count;i++) {
        NSControlTile *tile=[[NSControlTile alloc] initWithTitle:titles[i] subtitle:subs[i] symbol:symbols[i] active:NO];
        tile.frame=CGRectMake((i%2)*(tileW+gap),74+(i/2)*124,tileW,114);
        tile.accessibilityIdentifier=ids[i];
        [tile addTarget:self action:@selector(connectivityTileTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.connectivityPage addSubview:tile];
    }
    NSControlTile *hot=[[NSControlTile alloc] initWithTitle:@"个人热点" subtitle:@"预览控件" symbol:@"personalhotspot" active:NO];
    hot.frame=CGRectMake(0,326,w,62); [self.connectivityPage addSubview:hot];
    NSControlTile *vpn=[[NSControlTile alloc] initWithTitle:@"VPN" subtitle:@"预览控件" symbol:@"network" active:NO];
    vpn.frame=CGRectMake(0,398,w,62); [self.connectivityPage addSubview:vpn];
}

- (void)brightnessChanged:(UISlider *)sender { UIScreen.mainScreen.brightness = sender.value; }
- (void)togglePlayback {
    MPMusicPlayerController *player = MPMusicPlayerController.systemMusicPlayer;
    if (player.playbackState == MPMusicPlaybackStatePlaying) [player pause]; else [player play];
}
- (void)controlTileTapped:(NSControlTile *)tile {
    if (self.editingControls) return;
    NSString *identifier=tile.accessibilityIdentifier;
    if ([identifier isEqualToString:@"flashlight"]) { [self toggleFlashlight]; return; }
    if ([identifier isEqualToString:@"wifi"] || [identifier isEqualToString:@"bluetooth"] || [identifier isEqualToString:@"cellular"] || [identifier isEqualToString:@"vpn"] || [identifier isEqualToString:@"airplane"] || [identifier isEqualToString:@"hotspot"]) {
        [self.pages setContentOffset:CGPointMake(CGRectGetWidth(self.pages.bounds),0) animated:YES];
        return;
    }
    [self showInfoForIdentifier:identifier];
}
- (void)connectivityTileTapped:(NSControlTile *)tile {
    [self showInfoForIdentifier:tile.accessibilityIdentifier ?: @"unknown"];
}
- (void)showInfoForIdentifier:(NSString *)identifier {
    NSString *message = @"此控件的系统动作桥接尚未启用；当前不会伪造系统状态。";
    if ([identifier isEqualToString:@"wifi"] || [identifier isEqualToString:@"bluetooth"] || [identifier isEqualToString:@"cellular"]) message = @"iOS 不向普通第三方代码开放直接切换此系统开关的公开 API。后续需要针对 iOS 17.0 验证系统服务桥接。";
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:[self definitionForID:identifier][@"title"] ?: @"控制" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)toggleFlashlight {
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    if (!device || !device.hasTorch) { [self showInfoForIdentifier:@"flashlight"]; return; }
    NSError *error = nil;
    if (![device lockForConfiguration:&error]) {
        NSLog(@"[NeoStatus] Torch configuration failed: %@", error);
        [self showInfoForIdentifier:@"flashlight"];
        return;
    }
    BOOL shouldTurnOn = (device.torchMode != AVCaptureTorchModeOn);
    BOOL changed = YES;
    if (shouldTurnOn) {
        changed = [device setTorchModeOnWithLevel:1.0f error:&error];
    } else {
        device.torchMode = AVCaptureTorchModeOff;
    }
    [device unlockForConfiguration];
    if (!changed) NSLog(@"[NeoStatus] Torch mode change failed: %@", error);
    for (UIView *view in self.mainPage.subviews) {
        if ([view isKindOfClass:NSControlTile.class] && [((NSControlTile *)view).accessibilityIdentifier isEqualToString:@"flashlight"]) {
            ((NSControlTile *)view).active = device.torchMode == AVCaptureTorchModeOn;
            break;
        }
    }
}
- (void)toggleEditing {
    self.editingControls=!self.editingControls;
    [self.editButton setTitle:self.editingControls?@"完成":@"编辑" forState:UIControlStateNormal];
    [self layoutMainControls];
}
- (void)repositionExistingTiles {
    CGFloat gap = 9.0;
    CGFloat width = CGRectGetWidth(self.mainPage.bounds);
    CGFloat tileW = (width-gap)/2.0;
    CGFloat tileH = MIN(68, MAX(58, (CGRectGetHeight(self.mainPage.bounds)-220)/6.0));
    for (NSUInteger index = 0; index < self.controlIDs.count; index++) {
        NSString *identifier = self.controlIDs[index];
        NSControlTile *tile = nil;
        for (UIView *view in self.mainPage.subviews) {
            if ([view isKindOfClass:NSControlTile.class] && [view.accessibilityIdentifier isEqualToString:identifier]) { tile = (NSControlTile *)view; break; }
        }
        if (!tile) continue;
        tile.tag = 1000 + (NSInteger)index;
        [UIView animateWithDuration:0.10 animations:^{
            tile.frame = CGRectMake((index%2)*(tileW+gap), (index/2)*(tileH+gap), tileW, tileH);
        }];
        for (UIView *child in tile.subviews) if ([child isKindOfClass:UIButton.class] && child.tag >= 2000) child.tag = 2000 + (NSInteger)index;
    }
}

- (void)controlTileHeld:(UILongPressGestureRecognizer *)gesture {
    if (!self.editingControls) return;
    NSControlTile *tile = (NSControlTile *)gesture.view;
    NSInteger source = [self.controlIDs indexOfObject:tile.accessibilityIdentifier];
    if (source == NSNotFound) return;
    if (gesture.state == UIGestureRecognizerStateBegan) {
        self.draggingControlID = tile.accessibilityIdentifier;
        self.lastDragIndex = source;
        tile.transform = CGAffineTransformMakeScale(1.04, 1.04);
        tile.alpha = 0.72;
    } else if (gesture.state == UIGestureRecognizerStateChanged) {
        CGPoint point = [gesture locationInView:self.mainPage];
        CGFloat gap = 9.0;
        CGFloat tileW = (CGRectGetWidth(self.mainPage.bounds)-gap)/2.0;
        CGFloat tileH = MIN(68, MAX(58, (CGRectGetHeight(self.mainPage.bounds)-220)/6.0));
        NSInteger row = MAX(0, (NSInteger)(point.y/(tileH+gap)));
        NSInteger col = point.x > tileW+gap/2.0 ? 1 : 0;
        NSInteger target = MIN((NSInteger)self.controlIDs.count-1, row*2+col);
        NSInteger current = [self.controlIDs indexOfObject:self.draggingControlID];
        if (current != NSNotFound && target >= 0 && target != current && target < self.controlIDs.count) {
            [self.controlIDs removeObjectAtIndex:current];
            [self.controlIDs insertObject:self.draggingControlID atIndex:target];
            self.lastDragIndex = target;
            [self repositionExistingTiles];
        }
    } else if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled || gesture.state == UIGestureRecognizerStateFailed) {
        self.draggingControlID = nil;
        [NSConfig setObject:self.controlIDs forKey:NSLayoutDefaultsKey];
        [self layoutMainControls];
    }
}
- (void)removeControlButtonTapped:(UIButton *)sender {
    if (!self.editingControls) return;
    NSInteger index = sender.tag - 2000;
    if (index < 0 || index >= (NSInteger)self.controlIDs.count) return;
    [self.controlIDs removeObjectAtIndex:index];
    [NSConfig setObject:self.controlIDs forKey:NSLayoutDefaultsKey];
    [self layoutMainControls];
}
- (void)addControl {
    NSArray *all=@[@"wifi",@"cellular",@"bluetooth",@"airplane",@"hotspot",@"orientation",@"vpn",@"silent",@"focus",@"record",@"flashlight",@"screenmirror"];
    NSMutableArray *available = [NSMutableArray array];
    for (NSString *identifier in all) if (![self.controlIDs containsObject:identifier]) [available addObject:identifier];
    if (available.count == 0) {
        [self showInfoForIdentifier:@"controls-full"];
        return;
    }
    UIAlertController *picker = [UIAlertController alertControllerWithTitle:@"添加控制" message:@"选择要添加到控制中心的控件" preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *identifier in available) {
        NSString *title = [self definitionForID:identifier][@"title"];
        [picker addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self.controlIDs addObject:identifier];
            [NSConfig setObject:self.controlIDs forKey:NSLayoutDefaultsKey];
            [self layoutMainControls];
        }]];
    }
    [picker addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    picker.popoverPresentationController.sourceView = self.editButton;
    picker.popoverPresentationController.sourceRect = self.editButton.bounds;
    [self presentViewController:picker animated:YES completion:nil];
}
- (void)scrollViewDidScroll:(UIScrollView *)scrollView { self.pageControl.currentPage=(NSInteger)round(scrollView.contentOffset.x/MAX(1,CGRectGetWidth(scrollView.bounds))); }
- (void)pageChanged { [self.pages setContentOffset:CGPointMake(self.pageControl.currentPage*CGRectGetWidth(self.pages.bounds),0) animated:YES]; }
- (void)dismissPanel { [self dismissViewControllerAnimated:YES completion:nil]; }
@end
