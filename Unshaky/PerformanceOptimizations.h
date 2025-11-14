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
+ (instancetype)sharedInstance;
+ (BOOL)isInternalKeyboard:(int64_t)keyboardType;
+ (BOOL)isSupportedKeyboard:(int64_t)keyboardType;
+ (BOOL)isBluetoothKeyboard:(int64_t)keyboardType;

// IOKit-based detection methods for more accurate keyboard identification
- (void)refreshKeyboardList;
- (BOOL)isInternalKeyboardWithIOKit:(int64_t)keyboardType;
- (NSString *)getKeyboardNameForType:(int64_t)keyboardType;
- (NSArray<NSDictionary *> *)getAllConnectedKeyboards;

// Check if monitoring is needed based on connected keyboards and settings
- (BOOL)hasBuiltInKeyboard;
- (BOOL)hasExternalKeyboard;
- (BOOL)shouldMonitorWithIgnoreInternal:(BOOL)ignoreInternal ignoreExternal:(BOOL)ignoreExternal;
@end

#endif /* PerformanceOptimizations_h */