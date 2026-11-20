#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface NSConfig : NSObject
+ (BOOL)boolForKey:(NSString *)key defaultValue:(BOOL)fallback;
+ (nullable id)objectForKey:(NSString *)key;
+ (void)setObject:(nullable id)value forKey:(NSString *)key;
+ (void)resetAll;
+ (NSString *)domain;
+ (NSString *)changedNotification;
@end
NS_ASSUME_NONNULL_END
