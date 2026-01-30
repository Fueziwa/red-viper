//
//  InputManager.h
//  Red Viper - Virtual Boy Emulator for macOS
//
//  Singleton class for keyboard and gamepad input handling with Virtual Boy button mapping
//

#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import <GameController/GameController.h>

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

/// Gamepad button identifiers for binding configuration
typedef NS_ENUM(NSInteger, GamepadButton) {
    GamepadButtonA,               // Bottom face button (A on Xbox, X on PS)
    GamepadButtonB,               // Right face button (B on Xbox, Circle on PS)
    GamepadButtonX,               // Left face button (X on Xbox, Square on PS)
    GamepadButtonY,               // Top face button (Y on Xbox, Triangle on PS)
    GamepadButtonLeftShoulder,
    GamepadButtonRightShoulder,
    GamepadButtonLeftTrigger,
    GamepadButtonRightTrigger,
    GamepadButtonDpadUp,
    GamepadButtonDpadDown,
    GamepadButtonDpadLeft,
    GamepadButtonDpadRight,
    GamepadButtonLeftStickUp,
    GamepadButtonLeftStickDown,
    GamepadButtonLeftStickLeft,
    GamepadButtonLeftStickRight,
    GamepadButtonRightStickUp,
    GamepadButtonRightStickDown,
    GamepadButtonRightStickLeft,
    GamepadButtonRightStickRight,
    GamepadButtonMenu,            // Start/Options
    GamepadButtonOptions,         // Back/Share
    GamepadButtonCount
};

@interface InputManager : NSObject

/// Shared singleton instance
+ (instancetype)sharedManager;

/// Currently active game controller (nil if no gamepad connected)
@property (nonatomic, readonly, nullable) GCController *activeController;

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

#pragma mark - Gamepad Support

/// Poll gamepad state and return VB button flags
- (uint16_t)pollGamepadState;

/// Returns YES if a gamepad is connected and active
- (BOOL)isGamepadActive;

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

#pragma mark - Gamepad Binding Customization

/// Get which VB button a gamepad button is mapped to (returns VBButtonCount if unmapped)
- (VBButton)vbButtonForGamepadButton:(GamepadButton)gamepadButton;

/// Set which VB button a gamepad button maps to
- (void)setVBButton:(VBButton)vbButton forGamepadButton:(GamepadButton)gamepadButton;

/// Save gamepad bindings to UserDefaults
- (void)saveGamepadBindings;

/// Load gamepad bindings from UserDefaults (called on init)
- (void)loadGamepadBindings;

/// Reset gamepad bindings to defaults
- (void)resetGamepadBindingsToDefaults;

/// Get display name for a gamepad button
+ (NSString *)displayNameForGamepadButton:(GamepadButton)gamepadButton;

@end

/// C-callable function to get controller state (for V810_RControll in input_stubs)
uint16_t InputManager_currentControllerState(void);

NS_ASSUME_NONNULL_END
