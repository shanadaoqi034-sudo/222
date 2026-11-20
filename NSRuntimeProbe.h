#import <Foundation/Foundation.h>

@interface NSRuntimeProbe : NSObject
+ (void)writeSpringBoardRuntimeReport;
+ (void)writeSpringBoardRuntimeReportForReason:(NSString *)reason;
+ (NSString *)diagnosticDirectoryPath;
@end
