//
//  AdditionalOptimizations.h
//  Unshaky
//
//  Additional performance and energy optimizations
//

#ifndef AdditionalOptimizations_h
#define AdditionalOptimizations_h

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

// Adaptive processing based on system load
@interface SystemLoadMonitor : NSObject
+ (instancetype)sharedInstance;
- (BOOL)shouldReduceProcessing;
- (CGFloat)currentCPUUsage;
@end

// Smart event filtering based on user activity patterns
@interface ActivityPatternAnalyzer : NSObject
+ (instancetype)sharedInstance;
- (BOOL)shouldSkipProcessingForKeyCode:(CGKeyCode)keyCode;
- (void)recordKeyActivity:(CGKeyCode)keyCode timestamp:(NSTimeInterval)timestamp;
@end

// Memory pool for frequent allocations
@interface EventProcessingPool : NSObject
+ (instancetype)sharedInstance;
- (void)warmupPool;
- (void)cleanupPool;
@end

#endif /* AdditionalOptimizations_h */