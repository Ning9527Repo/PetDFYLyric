#pragma once
#import <UIKit/UIKit.h>
@interface PDLyricController : NSObject
+ (instancetype)shared;
- (void)start;
- (void)updateWithInfo:(NSDictionary *)info;
- (void)hide;
- (void)debugLog:(NSString *)line;
@end
