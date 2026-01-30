//
//  InputManager.h
//  Red Viper - Virtual Boy Emulator for macOS
//
//  Singleton class for keyboard input handling with Virtual Boy button mapping
//

#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>

NS_ASSUME_NONNULL_BEGIN

/// VB button identifiers (for UI configuration)
typedef NS_ENUM(NSInteger, VBButton) {
    VBButtonLPadUp,
    VBButtonLPadDown,
    VBButtonLPadLeft,
    VBButtonLPadRight,
    VBButtonRPadUp,
    VBButtonRPadDown,
    VBButtonRPadLeft,
    VBButtonRPadRight,
    VBButtonA,
    VBButtonB,
    VBButtonStart,
    VBButtonSelect,
    VBButtonL,
    VBButtonR,
    VBButtonCount  // 14 total
};

@interface InputManager : NSObject

/// Shared singleton instance
+ (instancetype)sharedManager;

/// Handle key press - call from EmulatorView keyDown:
- (void)keyDown:(NSEvent *)event;

/// Handle key release - call from EmulatorView keyUp:
- (void)keyUp:(NSEvent *)event;

/// Handle modifier key changes - call from EmulatorView flagsChanged:
- (void)flagsChanged:(NSEvent *)event;

/// Get current VB controller state (called by V810_RControll)
/// Returns 16-bit value with VB button flags
- (uint16_t)currentControllerState;

/// Clear all pressed keys (call on window focus loss)
- (void)clearAllKeys;

#pragma mark - Key Binding Customization

/// Get current key code for a button
- (unsigned short)keyCodeForButton:(VBButton)button;

/// Set key code for a button (does not save - call saveBindings after)
- (void)setKeyCode:(unsigned short)keyCode forButton:(VBButton)button;

/// Save bindings to UserDefaults
- (void)saveBindings;

/// Load bindings from UserDefaults (called on init)
- (void)loadBindings;

/// Reset to default bindings (does not save - call saveBindings after)
- (void)resetToDefaults;

/// Get display name for a button (e.g., "Left D-Pad Up", "A Button")
+ (NSString *)displayNameForButton:(VBButton)button;

@end

/// C-callable function to get controller state (for V810_RControll in input_stubs)
uint16_t InputManager_currentControllerState(void);

NS_ASSUME_NONNULL_END
