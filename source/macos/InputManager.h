//
//  InputManager.h
//  Red Viper - Virtual Boy Emulator for macOS
//
//  Singleton class for keyboard input handling with Virtual Boy button mapping
//

#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>

NS_ASSUME_NONNULL_BEGIN

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

@end

/// C-callable function to get controller state (for V810_RControll in input_stubs)
uint16_t InputManager_currentControllerState(void);

NS_ASSUME_NONNULL_END
