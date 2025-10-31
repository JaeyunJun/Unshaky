//
//  PerformanceOptimizations.h
//  Unshaky
//
//  Performance optimizations for modern macOS versions
//

#ifndef PerformanceOptimizations_h
#define PerformanceOptimizations_h

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

// Optimized timestamp cache to reduce system calls
@interface TimestampCache : NSObject
+ (instancetype)sharedInstance;
- (double)getCurrentTimestamp;
- (void)invalidateCache;
@end

// Keyboard type detection with extended support
@interface KeyboardTypeDetector : NSObject
+ (BOOL)isInternalKeyboard:(int64_t)keyboardType;
+ (BOOL)isSupportedKeyboard:(int64_t)keyboardType;
+ (BOOL)isBluetoothKeyboard:(int64_t)keyboardType;
@end

#endif /* PerformanceOptimizations_h */