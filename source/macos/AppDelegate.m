//
//  AppDelegate.m
//  Red Viper - Virtual Boy Emulator for macOS
//

#import "AppDelegate.h"
#import "MainWindow.h"
#import "EmulatorBridge.h"

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    // Initialize the emulator core first
    [[EmulatorBridge sharedBridge] initialize];
    
    // Create the main window
    NSRect frame = NSMakeRect(0, 0, 768, 448);  // 2x Virtual Boy resolution (384x224)
    NSWindowStyleMask style = NSWindowStyleMaskTitled |
                              NSWindowStyleMaskClosable |
                              NSWindowStyleMaskMiniaturizable |
                              NSWindowStyleMaskResizable;
    
    self.window = [[NSWindow alloc] initWithContentRect:frame
                                              styleMask:style
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    
    [self.window setTitle:@"Red Viper"];
    [self.window center];
    
    // Set up the content view with solid black background
    MainWindow *contentView = [[MainWindow alloc] initWithFrame:frame];
    [self.window setContentView:contentView];
    
    // Show the window
    [self.window makeKeyAndOrderFront:nil];
    
    // Activate the application
    [NSApp activateIgnoringOtherApps:YES];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    // Shutdown the emulator core
    [[EmulatorBridge sharedBridge] shutdown];
}

@end
