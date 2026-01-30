//
//  AppDelegate.h
//  Red Viper - Virtual Boy Emulator for macOS
//

#import <Cocoa/Cocoa.h>

@class EmulatorView;

@interface AppDelegate : NSObject <NSApplicationDelegate>

@property (strong, nonatomic) NSWindow *window;
@property (strong, nonatomic) EmulatorView *emulatorView;

@end
