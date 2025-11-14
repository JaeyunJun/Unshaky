//
//  ShakyPressPreventer.m
//  Unshaky
//
//  Created by Xinhong LIU on 2018-06-21.
//  Copyright © 2018 Nested Error. All rights reserved.
//

#import "ShakyPressPreventer.h"
#import "KeyboardLayouts.h"
#import "PerformanceOptimizations.h"

#define KEYCODE_SPACE 49

@implementation ShakyPressPreventer {
    NSTimeInterval lastPressedTimestamps[N_VIRTUAL_KEY];
    NSTimeInterval lastKeyDownTimestamps[N_VIRTUAL_KEY];  // Track KeyDown separately
    CGEventType lastPressedEventTypes[N_VIRTUAL_KEY];

    CGEventFlags lastEventFlagsAboutModifierKeysForSpace;
    BOOL cmdSpaceAllowance;
    BOOL workaroundForCmdSpace;
    BOOL aggressiveMode;
    BOOL statisticsDisabled;

    BOOL dismissNextEvent[N_VIRTUAL_KEY];
    int keyDelays[N_VIRTUAL_KEY];
    BOOL ignoreExternalKeyboard;
    BOOL ignoreInternalKeyboard;
    Handler statisticsHandler;

    CFMachPortRef eventTap;

    BOOL disabled;
    
    // Track the last key that was pressed (any key)
    CGKeyCode lastPressedKey;
    NSTimeInterval lastAnyKeyTimestamp;
}

static NSDictionary<NSNumber *, NSString *> *_keyCodeToString;

+ (ShakyPressPreventer *)sharedInstance {
    static ShakyPressPreventer *sharedInstance = nil;
    static dispatch_once_t onceToken; // onceToken = 0
    dispatch_once(&onceToken, ^{
        sharedInstance = [[ShakyPressPreventer alloc] init];
    });
    
    return sharedInstance;
}

- (instancetype)init {
    if (self = [super init]) {
        eventTap = NULL;
        [self loadKeyDelays];
        [self loadIgnoreExternalKeyboard];
        [self loadIgnoreInternalKeyboard];
        [self loadWorkaroundForCmdSpace];
        [self loadAggressiveMode];
        [self loadStatisticsDisabled];
        for (int i = 0; i < N_VIRTUAL_KEY; ++i) {
            lastPressedTimestamps[i] = 0.0;
            lastKeyDownTimestamps[i] = 0.0;
            lastPressedEventTypes[i] = 0;
            dismissNextEvent[i] = NO;
        }
        disabled = NO;
        lastPressedKey = 0;
        lastAnyKeyTimestamp = 0.0;
        
        // Listen for keyboard connection/disconnection events
        [[NSNotificationCenter defaultCenter] addObserver:self 
                                                 selector:@selector(keyboardConnectionChanged:) 
                                                     name:@"keyboard-connected" 
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self 
                                                 selector:@selector(keyboardConnectionChanged:) 
                                                     name:@"keyboard-disconnected" 
                                                   object:nil];
    }
    return self;
}

- (void)keyboardConnectionChanged:(NSNotification *)notification {
    NSLog(@"[Unshaky] Keyboard connection changed, updating monitoring state");
    // Wait a bit for the keyboard list to be refreshed
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self updateMonitoringState];
    });
}

// This initWithKeyDelays:ignoreExternalKeyboard: is used for testing purpose
- (instancetype)initWithKeyDelays:(int*)keyDelays_ ignoreExternalKeyboard:(BOOL)ignoreExternalKeyboard_ workaroundForCmdSpace:(BOOL)workaroundForCmdSpace_ aggressiveMode:(BOOL)aggressiveMode_ {
    if (self = [super init]) {
        ignoreExternalKeyboard = ignoreExternalKeyboard_;
        workaroundForCmdSpace = workaroundForCmdSpace_;
        aggressiveMode = aggressiveMode_;
        for (int i = 0; i < N_VIRTUAL_KEY; ++i) {
            keyDelays[i] = keyDelays_[i];
            lastPressedTimestamps[i] = 0.0;
            lastKeyDownTimestamps[i] = 0.0;
            lastPressedEventTypes[i] = 0;
            dismissNextEvent[i] = NO;
        }
        lastPressedKey = 0;
        lastAnyKeyTimestamp = 0.0;
    }
    return self;
}

- (void)loadKeyDelays {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSArray *delays = [defaults arrayForKey:@"delays"];

    // load enableds first
    int keyEnableds[N_VIRTUAL_KEY];
    NSArray *enableds = [defaults arrayForKey:@"enableds"];
    if (enableds == nil) {
        for (int i = 0; i < N_VIRTUAL_KEY; ++i) {
            keyEnableds[i] = true;
        }
    } else {
        for (int i = 0; i < N_VIRTUAL_KEY; ++i) {
            keyEnableds[i] = i >= [enableds count] ? true : [(NSNumber *)[enableds objectAtIndex:i] boolValue];
        }
    }

    // set delays
    if (delays == nil) {
        memset(keyDelays, 0, N_VIRTUAL_KEY * sizeof(int));
    } else {
        for (int i = 0; i < N_VIRTUAL_KEY; ++i) {
            keyDelays[i] = (i >= [delays count] || keyEnableds[i] == false) ?
                0 : [(NSNumber *)[delays objectAtIndex:i] intValue];
        }
    }
}

- (void)loadIgnoreExternalKeyboard {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    ignoreExternalKeyboard = [defaults boolForKey:@"ignoreExternalKeyboard"]; // default No
    [self updateMonitoringState];
}

- (void)loadIgnoreInternalKeyboard {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    ignoreInternalKeyboard = [defaults boolForKey:@"ignoreInternalKeyboard"]; // default No
    [self updateMonitoringState];
}

- (void)updateMonitoringState {
    // Refresh keyboard list to get current state
    [[KeyboardTypeDetector sharedInstance] refreshKeyboardList];
    
    // Check if monitoring is needed
    BOOL shouldMonitor = [[KeyboardTypeDetector sharedInstance] 
                          shouldMonitorWithIgnoreInternal:ignoreInternalKeyboard 
                          ignoreExternal:ignoreExternalKeyboard];
    
    // Enable or disable based on the result
    if (!shouldMonitor && [self eventTapEnabled]) {
        NSLog(@"[Unshaky] Disabling event tap - no keyboards to monitor");
        [self removeEventTap];
    } else if (shouldMonitor && ![self eventTapEnabled]) {
        NSLog(@"[Unshaky] Enabling event tap - keyboards need monitoring");
        [self setupEventTap];
    }
}

- (void)loadWorkaroundForCmdSpace {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    workaroundForCmdSpace = [defaults boolForKey:@"workaroundForCmdSpace"]; // default No
}

- (void)loadAggressiveMode {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    aggressiveMode = [defaults boolForKey:@"aggressiveMode"]; // default No
}

- (void)loadStatisticsDisabled {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    statisticsDisabled = [defaults boolForKey:@"statisticsDisabled"]; // default No
}

- (void)setDisabled:(BOOL)_disabled {
    disabled = _disabled;
    [[NSNotificationCenter defaultCenter] postNotificationName:@"enabled-toggled" object:nil];
}

- (BOOL)isDisabled {
    return disabled;
}

- (CGEventRef)filterShakyPressEvent:(CGEventRef)event {
    // Fast path: early return if disabled
    if (__builtin_expect(disabled, 0)) {
        return event;
    }

    // Direct processing - no unnecessary optimizations

    // The incoming keycode - get this first for early filtering
    CGKeyCode keyCode = (CGKeyCode)CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
    
    // Fast path: ignore unconfigured keys immediately
    if (__builtin_expect(keyCode >= N_VIRTUAL_KEY, 0)) {
        return event;
    }
    
    // Cache key delay for this key to avoid repeated array access
    int keyDelay = keyDelays[keyCode];
    if (__builtin_expect(keyDelay == 0, 0)) {
        return event;
    }

    // keyboard type filtering - only check if needed
    if (__builtin_expect(ignoreExternalKeyboard || ignoreInternalKeyboard, 0)) {
        int64_t keyboardType = CGEventGetIntegerValueField(event, kCGKeyboardEventKeyboardType);
        // Use IOKit-based keyboard type detection for better accuracy
        BOOL isInternalKeyboard = [[KeyboardTypeDetector sharedInstance] isInternalKeyboardWithIOKit:keyboardType];
        if (ignoreExternalKeyboard && !isInternalKeyboard) return event;
        if (ignoreInternalKeyboard && isInternalKeyboard) return event;
    }

    CGEventType eventType = CGEventGetType(event);
    CGEventFlags eventFlagsAboutModifierKeys = (kCGEventFlagMaskShift | kCGEventFlagMaskControl |
                                                kCGEventFlagMaskAlternate | kCGEventFlagMaskCommand |
                                                kCGEventFlagMaskSecondaryFn) & CGEventGetFlags(event);
    
    // Use optimized timestamp cache for better performance - always use cache
    double currentTimestamp = [[TimestampCache sharedInstance] getCurrentTimestamp];

    // Cache debug controller check for performance
    DebugViewController *debugController = _debugViewController;
    if (debugController != nil) {
        int64_t keyboardType = CGEventGetIntegerValueField(event, kCGKeyboardEventKeyboardType);
        [debugController appendEventToDebugTextview:currentTimestamp
                                       keyboardType:keyboardType
                                            keyCode:keyCode
                                          eventType:eventType
                        eventFlagsAboutModifierKeys:eventFlagsAboutModifierKeys
                                              delay:keyDelay];
    }

    if (lastPressedTimestamps[keyCode] != 0.0) {
        /** @ghost711: CMD+Space was pressed, which causes a duplicate pair of down/up
         keyEvents to occur 1-5 msecs after the "real" pair of events.
         - If the CMD key is released first, it will look like:
         CMD+Space Down
         Space Up
         CMD+Space Down
         CMD+Space Up
         - Whereas if the space bar is released first, it will be:
         CMD+Space Down
         CMD+Space Up
         CMD+Space Down
         CMD+Space Up
         - The issue only appears to happen with CMD+Space,
         not CMD+<any other key>, or <any other modifier key>+Space.*/
        // So here we allow one double-press to slip away

        // reset allowance to 1 - improved CMD+Space detection
        if (keyCode == KEYCODE_SPACE && (eventFlagsAboutModifierKeys & kCGEventFlagMaskCommand) && 
            1000 * (currentTimestamp - lastPressedTimestamps[keyCode]) >= keyDelays[keyCode]) {
            cmdSpaceAllowance = YES;
        }

        if (dismissNextEvent[keyCode]) {
            // dismiss the corresponding keyup event
            if (debugController != nil) {
                [debugController appendDismissed];
            }

            dismissNextEvent[keyCode] = NO;
            if (aggressiveMode) lastPressedTimestamps[keyCode] = currentTimestamp;
            return nil;
        }
        
        float msElapsed;
        // IMPROVED: Check time since last KeyDown, not last KeyUp
        // This prevents blocking legitimate fast typing where key is held down longer
        if (eventType == kCGEventKeyDown
            && lastPressedEventTypes[keyCode] == kCGEventKeyUp
            && lastKeyDownTimestamps[keyCode] != 0.0
            && (msElapsed = 1000 * (currentTimestamp - lastKeyDownTimestamps[keyCode])) < keyDelays[keyCode]) {

            // IMPROVEMENT: If a different key was pressed in between, allow this key press
            // This prevents blocking legitimate typing patterns like "aba", "cdc", etc.
            BOOL differentKeyPressedInBetween = (lastPressedKey != keyCode) && 
                                                (lastAnyKeyTimestamp > lastKeyDownTimestamps[keyCode]);
            
            if (differentKeyPressedInBetween) {
                // Allow this key press - it's part of normal typing pattern
                // Don't dismiss it
            } else if (keyCode == KEYCODE_SPACE && 
                (lastEventFlagsAboutModifierKeysForSpace & kCGEventFlagMaskCommand) &&
                (eventFlagsAboutModifierKeys & kCGEventFlagMaskCommand) && 
                workaroundForCmdSpace && cmdSpaceAllowance) {
                // let it slip away if allowance is 1 for CMD+SPACE - improved detection
                cmdSpaceAllowance = NO;
            } else {
                // dismiss the keydown event if it follows keyup event too soon
                if (debugController != nil) {
                    [debugController appendDismissed];
                }

                if (statisticsHandler != nil && !statisticsDisabled) {
                    // Move statistics to background thread to avoid blocking key processing
                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
                        self->statisticsHandler(keyCode);
                    });
                }
                dismissNextEvent[keyCode] = YES;
                return nil;
            }
        }
    } else if (keyCode == KEYCODE_SPACE && (eventFlagsAboutModifierKeys & kCGEventFlagMaskCommand)) {
        cmdSpaceAllowance = YES;
    }

    lastPressedTimestamps[keyCode] = currentTimestamp;
    lastPressedEventTypes[keyCode] = eventType;
    if (keyCode == KEYCODE_SPACE) lastEventFlagsAboutModifierKeysForSpace = eventFlagsAboutModifierKeys;
    
    // Track the last key pressed globally for improved filtering
    if (eventType == kCGEventKeyDown) {
        lastPressedKey = keyCode;
        lastAnyKeyTimestamp = currentTimestamp;
        lastKeyDownTimestamps[keyCode] = currentTimestamp;  // Track KeyDown time separately
    }
    
    return event;
}

- (BOOL)setupEventTap {
    // Only monitor KeyDown and KeyUp events - remove FlagsChanged to save energy
    CGEventMask eventMask = ((1 << kCGEventKeyDown) | (1 << kCGEventKeyUp));
    
    // Use kCGHeadInsertEventTap to run BEFORE Karabiner and other key remappers
    // This ensures Unshaky filters the original hardware key events
    eventTap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault,
                                eventMask, eventTapCallback, (__bridge void *)(self));
    if (!eventTap) {
        NSLog(@"Permission issue");
        return NO;
    }
    
    CFRunLoopSourceRef runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes);
    CGEventTapEnable(eventTap, true);
    CFRelease(runLoopSource);

    // No sleep assertion needed - key events are processed instantly

    return YES;
}

- (void)removeEventTap {
    if (eventTap == NULL) return;
    @try {
        // No energy management resources to release
        
        CFMachPortInvalidate(eventTap);
        CFRelease(eventTap);
        eventTap = NULL;
    }
    @catch(NSException *exception) {
        NSLog(@"Fail to remove event tap.");
    }
}

- (BOOL)eventTapEnabled {
    if (eventTap == NULL) return false;
    if (CGEventTapIsEnabled(eventTap) == false) return false;
    return true;
}

CGEventRef eventTapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon) {
    ShakyPressPreventer *kc = (__bridge ShakyPressPreventer*)refcon;
    return [kc filterShakyPressEvent: event];
}

- (void)setStatisticsHandler:(Handler)handler {
    statisticsHandler = handler;
}

+ (void)setKeyCodeToString:(NSDictionary<NSNumber *,NSString *> *)keyCodeToString {
    _keyCodeToString = keyCodeToString;
}
@end
