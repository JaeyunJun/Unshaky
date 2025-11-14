//
//  DebugViewController.m
//  Unshaky
//
//  Created by Xinhong LIU on 3/14/19.
//  Copyright © 2019 Nested Error. All rights reserved.
//

#import "DebugViewController.h"
#import "ShakyPressPreventer.h"
#import "KeyboardLayouts.h"
#import "PerformanceOptimizations.h"

@interface DebugViewController ()

@property (unsafe_unretained) IBOutlet NSTextView *textView;

@end

@implementation DebugViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do view setup here.
}

- (void)appendToDebugTextView:(NSString*)text {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSAttributedString* attr = [[NSAttributedString alloc]
                                    initWithString:text
                                    attributes:@{
                                                 NSForegroundColorAttributeName: [NSColor textColor],
                                                 NSFontAttributeName: [NSFont fontWithName:@"Courier New" size:10]
                                                 }];

        [[self.textView textStorage] appendAttributedString:attr];
        [self.textView scrollRangeToVisible: NSMakeRange(self.textView.string.length, 0)];
    });
}

- (void)appendEventToDebugTextview:(double)timestamp
                      keyboardType:(int64_t)keyboardType
                           keyCode:(CGKeyCode)keyCode
                         eventType:(CGEventType)eventType
       eventFlagsAboutModifierKeys:(CGEventFlags)eventFlagsAboutModifierKeys
                             delay:(int)delay {
    // Cache keyboard type descriptions to avoid repeated string allocations
    static NSString *internalDesc = nil;
    static NSString *externalDesc = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        internalDesc = @"Internal";
        externalDesc = @"External/BT";
    });
    
    NSDictionary<NSNumber *, NSString *> *keyCodeToString = [[KeyboardLayouts shared] keyCodeToString];
    NSString *keyDescription = keyCodeToString[@(keyCode)];
    if (keyDescription == nil) keyDescription = @"Unknown";
    
    // Use cached keyboard type descriptions
    NSString *keyboardTypeDesc = @"Unknown";
    if (keyboardType >= 58 && keyboardType <= 70) {
        keyboardTypeDesc = internalDesc;
    } else if ((keyboardType >= 0 && keyboardType <= 57) || (keyboardType >= 71 && keyboardType <= 200)) {
        keyboardTypeDesc = externalDesc;
    }
    
    NSString *eventString = [NSString stringWithFormat:@"%f Key(%3lld|%9s|%3d|%14s|%10llu|%3d) E(%u)",
                             timestamp, keyboardType, [keyboardTypeDesc UTF8String], keyCode, 
                             [keyDescription UTF8String], eventFlagsAboutModifierKeys, delay, eventType];
    [self appendToDebugTextView:[@"\n" stringByAppendingString:eventString]];
}

- (void)appendDismissed {
    [self appendToDebugTextView:@" DISMISSED"];
}

- (IBAction)copyClicked:(id)sender {
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard setString:self.textView.string forType:NSStringPboardType];
}

- (IBAction)clearClicked:(id)sender {
    self.textView.string = @"";
}

- (void)showConnectedKeyboards {
    NSArray<NSDictionary *> *keyboards = [[KeyboardTypeDetector sharedInstance] getAllConnectedKeyboards];
    
    NSMutableString *info = [NSMutableString stringWithString:@"\n========== Connected Keyboards ==========\n"];
    
    if (keyboards.count == 0) {
        [info appendString:@"No keyboards detected. Refreshing...\n"];
        [[KeyboardTypeDetector sharedInstance] refreshKeyboardList];
        
        // Try again after a short delay
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self showConnectedKeyboards];
        });
        return;
    }
    
    for (NSDictionary *keyboard in keyboards) {
        NSString *name = keyboard[@"productName"];
        NSString *transport = keyboard[@"transport"];
        BOOL isBuiltIn = [keyboard[@"isBuiltIn"] boolValue];
        NSNumber *vendorID = keyboard[@"vendorID"];
        NSNumber *productID = keyboard[@"productID"];
        
        [info appendFormat:@"\n📱 %@\n", name];
        [info appendFormat:@"   Type: %@\n", isBuiltIn ? @"Built-in (Internal)" : @"External"];
        [info appendFormat:@"   Transport: %@\n", [transport length] > 0 ? transport : @"N/A"];
        [info appendFormat:@"   Vendor ID: 0x%04X\n", [vendorID intValue]];
        [info appendFormat:@"   Product ID: 0x%04X\n", [productID intValue]];
    }
    
    [info appendString:@"\n=========================================\n"];
    
    [self appendToDebugTextView:info];
}

@end
