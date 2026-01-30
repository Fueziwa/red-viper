//
//  ControlsConfigController.h
//  Red Viper - Virtual Boy Emulator for macOS
//
//  Modal dialog controller for configuring keyboard controls
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface ControlsConfigController : NSObject

/// Show the configuration dialog as a modal sheet on the given window
- (void)showModalForWindow:(NSWindow *)parentWindow;

@end

NS_ASSUME_NONNULL_END
