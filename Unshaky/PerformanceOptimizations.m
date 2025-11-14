//
//  PerformanceOptimizations.m
//  Unshaky
//
//  Performance optimizations for modern macOS versions
//

#import "PerformanceOptimizations.h"
#import <mach/mach_time.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/hid/IOHIDDevice.h>
#import <IOKit/hid/IOHIDManager.h>

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
    
    // Very conservative cache duration of 2ms - maintains accuracy for key debouncing
    // Key debouncing requires precise timing, so we minimize caching
    if (currentMachTime - _lastMachTime > 2000000) { // ~2ms in nanoseconds
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

@implementation KeyboardTypeDetector {
    NSMutableDictionary<NSNumber *, NSDictionary *> *_keyboardCache;
    IOHIDManagerRef _hidManager;
    dispatch_queue_t _ioQueue;
}

+ (instancetype)sharedInstance {
    static KeyboardTypeDetector *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[KeyboardTypeDetector alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    if (self = [super init]) {
        _keyboardCache = [NSMutableDictionary dictionary];
        _ioQueue = dispatch_queue_create("com.unshaky.keyboard.detection", DISPATCH_QUEUE_SERIAL);
        [self setupHIDManager];
        [self refreshKeyboardList];
    }
    return self;
}

- (void)setupHIDManager {
    _hidManager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    if (!_hidManager) {
        NSLog(@"Failed to create HID manager");
        return;
    }
    
    // Filter for keyboard devices
    NSDictionary *matchingDict = @{
        @(kIOHIDDeviceUsagePageKey): @(kHIDPage_GenericDesktop),
        @(kIOHIDDeviceUsageKey): @(kHIDUsage_GD_Keyboard)
    };
    
    IOHIDManagerSetDeviceMatching(_hidManager, (__bridge CFDictionaryRef)matchingDict);
    
    // Register callbacks for device connection/disconnection
    IOHIDManagerRegisterDeviceMatchingCallback(_hidManager, deviceMatchingCallback, (__bridge void *)self);
    IOHIDManagerRegisterDeviceRemovalCallback(_hidManager, deviceRemovalCallback, (__bridge void *)self);
    
    IOHIDManagerScheduleWithRunLoop(_hidManager, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
    IOHIDManagerOpen(_hidManager, kIOHIDOptionsTypeNone);
}

static void deviceMatchingCallback(void *context, IOReturn result, void *sender, IOHIDDeviceRef device) {
    KeyboardTypeDetector *detector = (__bridge KeyboardTypeDetector *)context;
    NSLog(@"[Unshaky] Keyboard connected");
    [detector refreshKeyboardList];
    
    // Notify ShakyPressPreventer to update monitoring state
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"keyboard-connected" object:nil];
    });
}

static void deviceRemovalCallback(void *context, IOReturn result, void *sender, IOHIDDeviceRef device) {
    KeyboardTypeDetector *detector = (__bridge KeyboardTypeDetector *)context;
    NSLog(@"[Unshaky] Keyboard disconnected");
    [detector refreshKeyboardList];
    
    // Notify ShakyPressPreventer to update monitoring state
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"keyboard-disconnected" object:nil];
    });
}

- (void)refreshKeyboardList {
    dispatch_async(_ioQueue, ^{
        if (!self->_hidManager) return;
        
        NSSet *devices = (__bridge NSSet *)IOHIDManagerCopyDevices(self->_hidManager);
        NSMutableDictionary *newCache = [NSMutableDictionary dictionary];
        
        for (id device in devices) {
            IOHIDDeviceRef deviceRef = (__bridge IOHIDDeviceRef)device;
            
            // Get keyboard properties
            NSNumber *vendorID = (__bridge NSNumber *)IOHIDDeviceGetProperty(deviceRef, CFSTR(kIOHIDVendorIDKey));
            NSNumber *productID = (__bridge NSNumber *)IOHIDDeviceGetProperty(deviceRef, CFSTR(kIOHIDProductIDKey));
            NSString *transport = (__bridge NSString *)IOHIDDeviceGetProperty(deviceRef, CFSTR(kIOHIDTransportKey));
            NSString *productName = (__bridge NSString *)IOHIDDeviceGetProperty(deviceRef, CFSTR(kIOHIDProductKey));
            NSNumber *locationID = (__bridge NSNumber *)IOHIDDeviceGetProperty(deviceRef, CFSTR(kIOHIDLocationIDKey));
            
            // Determine if it's built-in
            BOOL isBuiltIn = NO;
            
            // Filter out virtual keyboards (Karabiner, etc.)
            BOOL isVirtualKeyboard = [productName containsString:@"Virtual"] ||
                                     [productName containsString:@"Karabiner"] ||
                                     [productName containsString:@"DriverKit"];
            
            // Apple's built-in keyboards typically have:
            // - Transport: "ADB", "SPI" or empty
            // - VendorID: 0x05ac (Apple)
            // - Product name contains "Apple Internal Keyboard"
            if (!isVirtualKeyboard && [vendorID intValue] == 0x05ac) { // Apple vendor ID
                if ([transport isEqualToString:@"ADB"] || 
                    [transport isEqualToString:@"SPI"] ||
                    [transport length] == 0 ||
                    [productName containsString:@"Internal"] ||
                    [productName containsString:@"Built-in"]) {
                    isBuiltIn = YES;
                }
            }
            
            NSDictionary *keyboardInfo = @{
                @"vendorID": vendorID ?: @0,
                @"productID": productID ?: @0,
                @"transport": transport ?: @"",
                @"productName": productName ?: @"Unknown",
                @"locationID": locationID ?: @0,
                @"isBuiltIn": @(isBuiltIn)
            };
            
            // Use locationID as key for caching
            if (locationID) {
                newCache[locationID] = keyboardInfo;
            }
        }
        
        @synchronized(self) {
            self->_keyboardCache = newCache;
        }
        
        NSLog(@"Detected %lu keyboard(s)", (unsigned long)[newCache count]);
        for (NSNumber *key in newCache) {
            NSDictionary *info = newCache[key];
            NSLog(@"  - %@ (Built-in: %@, Transport: %@)", 
                  info[@"productName"], 
                  [info[@"isBuiltIn"] boolValue] ? @"YES" : @"NO",
                  info[@"transport"]);
        }
    });
}

- (BOOL)isInternalKeyboardWithIOKit:(int64_t)keyboardType {
    // First try the cache-based detection
    @synchronized(self) {
        // Check if we have any built-in keyboard in cache
        for (NSDictionary *info in [_keyboardCache allValues]) {
            if ([info[@"isBuiltIn"] boolValue]) {
                // If we have a built-in keyboard detected, use enhanced logic
                // Internal keyboards typically have type 58-70
                if (keyboardType >= 58 && keyboardType <= 70) {
                    return YES;
                }
            }
        }
    }
    
    // Fallback to simple type-based detection
    return [KeyboardTypeDetector isInternalKeyboard:keyboardType];
}

- (NSString *)getKeyboardNameForType:(int64_t)keyboardType {
    @synchronized(self) {
        for (NSDictionary *info in [_keyboardCache allValues]) {
            // This is a simplified mapping - in reality, we can't directly map
            // CGEvent keyboard type to IOKit device, but we can provide info
            return info[@"productName"];
        }
    }
    return @"Unknown Keyboard";
}

- (NSArray<NSDictionary *> *)getAllConnectedKeyboards {
    @synchronized(self) {
        return [_keyboardCache allValues];
    }
}

- (BOOL)hasBuiltInKeyboard {
    @synchronized(self) {
        for (NSDictionary *info in [_keyboardCache allValues]) {
            if ([info[@"isBuiltIn"] boolValue]) {
                return YES;
            }
        }
    }
    return NO;
}

- (BOOL)hasExternalKeyboard {
    @synchronized(self) {
        for (NSDictionary *info in [_keyboardCache allValues]) {
            if (![info[@"isBuiltIn"] boolValue]) {
                return YES;
            }
        }
    }
    return NO;
}

- (BOOL)shouldMonitorWithIgnoreInternal:(BOOL)ignoreInternal ignoreExternal:(BOOL)ignoreExternal {
    // If both are ignored, no need to monitor
    if (ignoreInternal && ignoreExternal) {
        NSLog(@"[Unshaky] Both internal and external keyboards are ignored. Monitoring disabled.");
        return NO;
    }
    
    BOOL hasBuiltIn = [self hasBuiltInKeyboard];
    BOOL hasExternal = [self hasExternalKeyboard];
    
    // If ignoring internal and only internal keyboard exists, no need to monitor
    if (ignoreInternal && hasBuiltIn && !hasExternal) {
        NSLog(@"[Unshaky] Only internal keyboard detected and it's ignored. Monitoring disabled.");
        return NO;
    }
    
    // If ignoring external and only external keyboard exists, no need to monitor
    if (ignoreExternal && !hasBuiltIn && hasExternal) {
        NSLog(@"[Unshaky] Only external keyboard detected and it's ignored. Monitoring disabled.");
        return NO;
    }
    
    // Otherwise, monitoring is needed
    NSLog(@"[Unshaky] Monitoring enabled. Built-in: %@, External: %@, Ignore Internal: %@, Ignore External: %@",
          hasBuiltIn ? @"YES" : @"NO",
          hasExternal ? @"YES" : @"NO",
          ignoreInternal ? @"YES" : @"NO",
          ignoreExternal ? @"YES" : @"NO");
    return YES;
}

- (void)dealloc {
    if (_hidManager) {
        IOHIDManagerClose(_hidManager, kIOHIDOptionsTypeNone);
        CFRelease(_hidManager);
    }
}

// Class methods for backward compatibility
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