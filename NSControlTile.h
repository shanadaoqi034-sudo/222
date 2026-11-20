#import <UIKit/UIKit.h>

@interface NSControlTile : UIControl
@property(nonatomic, copy) NSString *titleText;
@property(nonatomic, copy) NSString *subtitleText;
@property(nonatomic, copy) NSString *symbolName;
@property(nonatomic, strong) UIColor *accentColor;
@property(nonatomic, getter=isActive) BOOL active;
- (instancetype)initWithTitle:(NSString *)title subtitle:(NSString *)subtitle symbol:(NSString *)symbol active:(BOOL)active;
@end
