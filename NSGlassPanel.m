#import "NSGlassPanel.h"
#import "NSConfig.h"

@implementation NSGlassPanel
- (instancetype)initWithFrame:(CGRect)frame cornerRadius:(CGFloat)radius {
    BOOL glassEnabled = [NSConfig boolForKey:@"GlassEnabled" defaultValue:YES];
    BOOL roundedEnabled = [NSConfig boolForKey:@"RoundedModulesEnabled" defaultValue:YES];
    CGFloat effectiveRadius = roundedEnabled ? radius : MIN(radius, 8.0);
    UIBlurEffect *blur = glassEnabled ? [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterialDark] : nil;
    self = [super initWithEffect:blur];
    if (self) {
        self.frame = frame;
        self.clipsToBounds = YES;
        self.layer.cornerRadius = effectiveRadius;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.borderWidth = roundedEnabled ? 0.7 : 0.0;
        self.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.24].CGColor;
        self.contentView.backgroundColor = glassEnabled ? [UIColor colorWithWhite:1 alpha:0.055] : [UIColor colorWithWhite:0.08 alpha:0.94];
    }
    return self;
}
@end
