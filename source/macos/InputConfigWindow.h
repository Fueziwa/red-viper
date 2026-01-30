//
//  InputConfigWindow.h
//  Red Viper - Virtual Boy Emulator for macOS
//
//  Standalone window controller for keyboard and gamepad input configuration
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface InputConfigWindow : NSWindowController

/// Show the input configuration window (creates if needed)
+ (void)showWindow;

@end

NS_ASSUME_NONNULL_END
