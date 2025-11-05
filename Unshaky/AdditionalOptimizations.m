//
//  AdditionalOptimizations.m
//  Unshaky
//
//  Additional performance and energy optimizations
//

#import "AdditionalOptimizations.h"
#import <sys/sysctl.h>
#import <mach/mach.h>

// System Load Monitor Implementation
@implementation SystemLoadMonitor {
    NSTimeInterval _lastCPUCheck;
    CGFloat _cachedCPUUsage;
    NSTimeInterval _cpuCheckInterval;
}

+ (instancetype)sharedInstance {
    static SystemLoadMonitor *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[SystemLoadMonitor alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    if (self = [super init]) {
        _lastCPUCheck = 0.0;
        _cachedCPUUsage = 0.0;
        _cpuCheckInterval = 10.0; // Check CPU every 10 seconds
    }
    return self;
}

- (BOOL)shouldReduceProcessing {
    CGFloat cpuUsage = [self currentCPUUsage];
    // Reduce processing if CPU usage is above 70%
    return cpuUsage > 0.7;
}

- (CGFloat)currentCPUUsage {
    NSTimeInterval currentTime = CACurrentMediaTime();
    if (currentTime - _lastCPUCheck > _cpuCheckInterval) {
        _cachedCPUUsage = [self calculateCPUUsage];
        _lastCPUCheck = currentTime;
    }
    return _cachedCPUUsage;
}

- (CGFloat)calculateCPUUsage {
    kern_return_t kr;
    task_info_data_t tinfo;
    mach_msg_type_number_t task_info_count = TASK_INFO_MAX;
    
    kr = task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)tinfo, &task_info_count);
    if (kr != KERN_SUCCESS) {
        return 0.0;
    }
    
    task_basic_info_t basic_info = (task_basic_info_t)tinfo;
    
    // Simple CPU usage estimation
    static uint64_t last_user_time = 0;
    static uint64_t last_system_time = 0;
    static NSTimeInterval last_check_time = 0;
    
    uint64_t current_user_time = basic_info->user_time.seconds * 1000000 + basic_info->user_time.microseconds;
    uint64_t current_system_time = basic_info->system_time.seconds * 1000000 + basic_info->system_time.microseconds;
    NSTimeInterval current_time = CACurrentMediaTime();
    
    if (last_check_time > 0) {
        uint64_t user_diff = current_user_time - last_user_time;
        uint64_t system_diff = current_system_time - last_system_time;
        NSTimeInterval time_diff = current_time - last_check_time;
        
        CGFloat usage = (user_diff + system_diff) / (time_diff * 1000000.0);
        
        last_user_time = current_user_time;
        last_system_time = current_system_time;
        last_check_time = current_time;
        
        return MIN(usage, 1.0);
    }
    
    last_user_time = current_user_time;
    last_system_time = current_system_time;
    last_check_time = current_time;
    
    return 0.0;
}

@end

// Activity Pattern Analyzer Implementation
@implementation ActivityPatternAnalyzer {
    NSMutableDictionary<NSNumber *, NSNumber *> *_keyFrequency;
    NSTimeInterval _lastAnalysis;
    NSTimeInterval _analysisInterval;
}

+ (instancetype)sharedInstance {
    static ActivityPatternAnalyzer *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[ActivityPatternAnalyzer alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    if (self = [super init]) {
        _keyFrequency = [[NSMutableDictionary alloc] init];
        _lastAnalysis = 0.0;
        _analysisInterval = 60.0; // Analyze patterns every minute
    }
    return self;
}

- (BOOL)shouldSkipProcessingForKeyCode:(CGKeyCode)keyCode {
    // Skip processing for very infrequently used keys
    NSNumber *keyNumber = @(keyCode);
    NSNumber *frequency = _keyFrequency[keyNumber];
    
    if (!frequency) return NO;
    
    // If key is used less than once per minute on average, reduce processing
    return [frequency intValue] < 1;
}

- (void)recordKeyActivity:(CGKeyCode)keyCode timestamp:(NSTimeInterval)timestamp {
    NSNumber *keyNumber = @(keyCode);
    NSNumber *currentCount = _keyFrequency[keyNumber] ?: @(0);
    _keyFrequency[keyNumber] = @([currentCount intValue] + 1);
    
    // Periodically reset counters to adapt to changing patterns
    if (timestamp - _lastAnalysis > _analysisInterval) {
        [self resetCounters];
        _lastAnalysis = timestamp;
    }
}

- (void)resetCounters {
    // Decay all counters by half to adapt to changing usage patterns
    for (NSNumber *key in _keyFrequency.allKeys) {
        NSNumber *count = _keyFrequency[key];
        _keyFrequency[key] = @([count intValue] / 2);
    }
}

@end

// Event Processing Pool Implementation
@implementation EventProcessingPool {
    NSMutableArray *_eventPool;
    NSUInteger _poolSize;
}

+ (instancetype)sharedInstance {
    static EventProcessingPool *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[EventProcessingPool alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    if (self = [super init]) {
        _poolSize = 100;
        _eventPool = [[NSMutableArray alloc] initWithCapacity:_poolSize];
    }
    return self;
}

- (void)warmupPool {
    // Pre-allocate objects to avoid allocation overhead during event processing
    for (NSUInteger i = 0; i < _poolSize; i++) {
        [_eventPool addObject:[[NSMutableDictionary alloc] init]];
    }
}

- (void)cleanupPool {
    [_eventPool removeAllObjects];
}

@end