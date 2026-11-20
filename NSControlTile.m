#import "NSControlTile.h"
#import "NSGlassPanel.h"
#import "NSConfig.h"

@interface NSControlTile ()
@property(nonatomic,strong) NSGlassPanel *glass;
@property(nonatomic,strong) UIImageView *symbolView;
@property(nonatomic,strong) UILabel *titleLabel;
@property(nonatomic,strong) UILabel *subtitleLabel;
@end

@implementation NSControlTile
- (instancetype)initWithTitle:(NSString *)title subtitle:(NSString *)subtitle symbol:(NSString *)symbol active:(BOOL)active {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _titleText = title; _subtitleText = subtitle; _symbolName = symbol; _active = active;
        _accentColor = [NSConfig boolForKey:@"ColoredGlyphsEnabled" defaultValue:YES] ? [UIColor colorWithRed:0.12 green:0.58 blue:1 alpha:1] : UIColor.whiteColor;
        self.glass = [[NSGlassPanel alloc] initWithFrame:self.bounds cornerRadius:24];
        self.glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:self.glass];
        self.symbolView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol]];
        self.symbolView.tintColor = active ? _accentColor : UIColor.whiteColor;
        self.symbolView.contentMode = UIViewContentModeScaleAspectFit;
        [self addSubview:self.symbolView];
        self.titleLabel = [[UILabel alloc] init];
        self.titleLabel.text = title; self.titleLabel.textColor = UIColor.whiteColor;
        self.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        [self addSubview:self.titleLabel];
        self.subtitleLabel = [[UILabel alloc] init];
        self.subtitleLabel.text = subtitle; self.subtitleLabel.textColor = [UIColor colorWithWhite:1 alpha:0.68];
        self.subtitleLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightRegular];
        [self addSubview:self.subtitleLabel];
        self.layer.cornerRadius = [NSConfig boolForKey:@"RoundedModulesEnabled" defaultValue:YES] ? 24 : 8;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        [self addTarget:self action:@selector(tapped) forControlEvents:UIControlEventTouchUpInside];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat h = CGRectGetHeight(self.bounds);
    self.symbolView.frame = CGRectMake(13, 13, 25, 25);
    self.titleLabel.frame = CGRectMake(14, h-39, CGRectGetWidth(self.bounds)-25, 17);
    self.subtitleLabel.frame = CGRectMake(14, h-23, CGRectGetWidth(self.bounds)-25, 14);
}
- (void)setActive:(BOOL)active {
    _active = active;
    self.symbolView.tintColor = active ? self.accentColor : UIColor.whiteColor;
}
- (void)tapped {
    // Visual prototype only. System actions are intentionally not faked here.
    [UIView animateWithDuration:0.12 animations:^{ self.transform = CGAffineTransformMakeScale(0.96, 0.96); self.alpha = 0.88; } completion:^(BOOL done) {
        [UIView animateWithDuration:0.18 animations:^{ self.transform = CGAffineTransformIdentity; self.alpha = 1; }];
    }];
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}
@end
