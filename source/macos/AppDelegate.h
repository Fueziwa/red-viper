//
//  AppDelegate.h
//  Red Viper - Virtual Boy Emulator for macOS
//

#import <Cocoa/Cocoa.h>

@class EmulatorView;

@interface AppDelegate : NSObject <NSApplicationDelegate>

@property (strong, nonatomic) NSWindow *window;
@property (strong, nonatomic) EmulatorView *emulatorView;

/// Increase display scale (Cmd+)
- (IBAction)scaleUp:(id)sender;

/// Decrease display scale (Cmd-)
- (IBAction)scaleDown:(id)sender;

@end
