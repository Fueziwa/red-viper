//
//  InputManager.m
//  Red Viper - Virtual Boy Emulator for macOS
//
//  Singleton class for keyboard input handling with Virtual Boy button mapping
//

#import "InputManager.h"
#include "vb_dsp.h"

@implementation InputManager {
    /// Maps keyCode (NSNumber) -> VB button flag (NSNumber)
    NSDictionary<NSNumber *, NSNumber *> *_keyToButtonMap;
    
    /// Maps keyCode for modifier keys -> VB button flag
    NSDictionary<NSNumber *, NSNumber *> *_modifierButtonMap;
    
    /// Currently pressed key codes
    NSMutableSet<NSNumber *> *_pressedKeys;
}

#pragma mark - Singleton

+ (instancetype)sharedManager {
    static InputManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[InputManager alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _pressedKeys = [[NSMutableSet alloc] init];
        [self setupDefaultKeyMapping];
    }
    return self;
}

#pragma mark - Key Mapping Setup

- (void)setupDefaultKeyMapping {
    // Default key mapping from CONTEXT.md:
    // Left D-pad: WASD
    // A button: K
    // B button: J
    // Right D-pad: P=up, ;=down, L=left, '=right
    // Start: Return
    // Select: Shift (handled via flagsChanged)
    // L trigger: 1
    // R trigger: 2
    
    _keyToButtonMap = @{
        // Left D-pad: WASD
        @(kVK_ANSI_W): @(VB_LPAD_U),  // W -> Left Up
        @(kVK_ANSI_S): @(VB_LPAD_D),  // S -> Left Down
        @(kVK_ANSI_A): @(VB_LPAD_L),  // A -> Left Left
        @(kVK_ANSI_D): @(VB_LPAD_R),  // D -> Left Right
        
        // A/B buttons
        @(kVK_ANSI_K): @(VB_KEY_A),   // K -> A
        @(kVK_ANSI_J): @(VB_KEY_B),   // J -> B
        
        // Right D-pad: P, ;, L, '
        @(kVK_ANSI_P):         @(VB_RPAD_U),  // P -> Right Up
        @(kVK_ANSI_Semicolon): @(VB_RPAD_D),  // ; -> Right Down
        @(kVK_ANSI_L):         @(VB_RPAD_L),  // L -> Right Left
        @(kVK_ANSI_Quote):     @(VB_RPAD_R),  // ' -> Right Right
        
        // Start
        @(kVK_Return): @(VB_KEY_START),  // Return -> Start
        
        // Triggers
        @(kVK_ANSI_1): @(VB_KEY_L),  // 1 -> L Trigger
        @(kVK_ANSI_2): @(VB_KEY_R),  // 2 -> R Trigger
    };
    
    // Modifier keys handled separately via flagsChanged
    _modifierButtonMap = @{
        @(kVK_Shift): @(VB_KEY_SELECT),  // Shift -> Select
    };
}

#pragma mark - Event Handling

- (void)keyDown:(NSEvent *)event {
    // Ignore key repeats (macOS sends repeated events while key is held)
    if ([event isARepeat]) {
        return;
    }
    
    NSNumber *keyCode = @(event.keyCode);
    [_pressedKeys addObject:keyCode];
}

- (void)keyUp:(NSEvent *)event {
    NSNumber *keyCode = @(event.keyCode);
    [_pressedKeys removeObject:keyCode];
}

- (void)flagsChanged:(NSEvent *)event {
    // Handle modifier keys (Shift for Select)
    // Check if Shift is held
    BOOL shiftHeld = (event.modifierFlags & NSEventModifierFlagShift) != 0;
    
    NSNumber *shiftKeyCode = @(kVK_Shift);
    if (shiftHeld) {
        [_pressedKeys addObject:shiftKeyCode];
    } else {
        [_pressedKeys removeObject:shiftKeyCode];
    }
}

#pragma mark - Controller State

- (uint16_t)currentControllerState {
    // Start with battery OK flag (bit 1 set, bit 0 clear)
    uint16_t result = 0x0002;
    
    // Check each pressed key and OR in the corresponding button flag
    for (NSNumber *keyCode in _pressedKeys) {
        // Check regular keys
        NSNumber *buttonFlag = _keyToButtonMap[keyCode];
        if (buttonFlag) {
            result |= [buttonFlag unsignedShortValue];
        }
        
        // Check modifier keys
        NSNumber *modifierFlag = _modifierButtonMap[keyCode];
        if (modifierFlag) {
            result |= [modifierFlag unsignedShortValue];
        }
    }
    
    return result;
}

- (void)clearAllKeys {
    [_pressedKeys removeAllObjects];
}

@end

#pragma mark - C-Callable Function

uint16_t InputManager_currentControllerState(void) {
    return [[InputManager sharedManager] currentControllerState];
}
