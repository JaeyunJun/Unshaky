//
//  PerformanceOptimizations.m
//  Unshaky
//
//  Performance optimizations for modern macOS versions
//

#import "PerformanceOptimizations.h"
#import <mach/mach_time.h>

@implementation TimestampCache {
    double _cachedTimestamp;
    uint64_t _lastMachTime;
    double _machTimeToSeconds;
}

+ (instancetype)sharedInstance {
    static TimestampCache *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[TimestampCache alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    if (self = [super init]) {
        mach_timebase_info_data_t timebase;
        mach_timebase_info(&timebase);
        _machTimeToSeconds = (double)timebase.numer / (double)timebase.denom / 1e9;
        _cachedTimestamp = 0;
        _lastMachTime = 0;
    }
    return self;
}

- (double)getCurrentTimestamp {
    uint64_t currentMachTime = mach_absolute_time();
    
    // Increase cache duration to 5ms for better energy efficiency
    if (currentMachTime - _lastMachTime > 5000000) { // ~5ms in nanoseconds
        _cachedTimestamp = currentMachTime * _machTimeToSeconds;
        _lastMachTime = currentMachTime;
    }
    
    return _cachedTimestamp;
}

- (void)invalidateCache {
    _cachedTimestamp = 0;
    _lastMachTime = 0;
}

@end

@implementation KeyboardTypeDetector

+ (BOOL)isInternalKeyboard:(int64_t)keyboardType {
    // Extended support for various MacBook internal keyboard types
    // 58: Pre-2018 MacBook Pro
    // 59: 2018 MacBook Pro 15"
    // 60-70: Newer MacBook models (including M1/M2/M3 series)
    return (keyboardType >= 58 && keyboardType <= 70);
}

+ (BOOL)isBluetoothKeyboard:(int64_t)keyboardType {
    // Bluetooth keyboards typically have different type ranges
    // Common Bluetooth keyboard types: 0-57, 71-200
    // This helps identify keyboards that might need different handling
    return (keyboardType >= 0 && keyboardType <= 57) || (keyboardType >= 71 && keyboardType <= 200);
}

+ (BOOL)isSupportedKeyboard:(int64_t)keyboardType {
    // Support both internal and common external keyboards
    return keyboardType >= 0 && keyboardType <= 200;
}

@end