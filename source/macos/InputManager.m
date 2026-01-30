//
//  InputManager.m
//  Red Viper - Virtual Boy Emulator for macOS
//
//  Singleton class for keyboard input handling with Virtual Boy button mapping
//

#import "InputManager.h"
#include "vb_dsp.h"

/// UserDefaults key for storing key bindings
static NSString * const kRedViperKeyBindingsKey = @"RedViperKeyBindings";

/// Maps VBButton enum values to VB hardware button flags
static const uint16_t VBButtonFlags[VBButtonCount] = {
    VB_LPAD_U,      // VBButtonLPadUp
    VB_LPAD_D,      // VBButtonLPadDown
    VB_LPAD_L,      // VBButtonLPadLeft
    VB_LPAD_R,      // VBButtonLPadRight
    VB_RPAD_U,      // VBButtonRPadUp
    VB_RPAD_D,      // VBButtonRPadDown
    VB_RPAD_L,      // VBButtonRPadLeft
    VB_RPAD_R,      // VBButtonRPadRight
    VB_KEY_A,       // VBButtonA
    VB_KEY_B,       // VBButtonB
    VB_KEY_START,   // VBButtonStart
    VB_KEY_SELECT,  // VBButtonSelect
    VB_KEY_L,       // VBButtonL
    VB_KEY_R,       // VBButtonR
};

@implementation InputManager {
    /// Maps VBButton (NSNumber) -> keyCode (NSNumber)
    NSMutableDictionary<NSNumber *, NSNumber *> *_buttonToKeyMap;
    
    /// Maps keyCode (NSNumber) -> VB button flag (NSNumber) - rebuilt from buttonToKeyMap
    NSMutableDictionary<NSNumber *, NSNumber *> *_keyToButtonMap;
    
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
        _buttonToKeyMap = [[NSMutableDictionary alloc] init];
        _keyToButtonMap = [[NSMutableDictionary alloc] init];
        [self loadBindings];
    }
    return self;
}

#pragma mark - Key Mapping Setup

- (void)resetToDefaults {
    // Default key mapping from CONTEXT.md:
    // Left D-pad: WASD
    // A button: K
    // B button: J
    // Right D-pad: P=up, ;=down, L=left, '=right
    // Start: Return
    // Select: Shift
    // L trigger: 1
    // R trigger: 2
    
    [_buttonToKeyMap removeAllObjects];
    
    _buttonToKeyMap[@(VBButtonLPadUp)]    = @(kVK_ANSI_W);
    _buttonToKeyMap[@(VBButtonLPadDown)]  = @(kVK_ANSI_S);
    _buttonToKeyMap[@(VBButtonLPadLeft)]  = @(kVK_ANSI_A);
    _buttonToKeyMap[@(VBButtonLPadRight)] = @(kVK_ANSI_D);
    
    _buttonToKeyMap[@(VBButtonRPadUp)]    = @(kVK_ANSI_P);
    _buttonToKeyMap[@(VBButtonRPadDown)]  = @(kVK_ANSI_Semicolon);
    _buttonToKeyMap[@(VBButtonRPadLeft)]  = @(kVK_ANSI_L);
    _buttonToKeyMap[@(VBButtonRPadRight)] = @(kVK_ANSI_Quote);
    
    _buttonToKeyMap[@(VBButtonA)]         = @(kVK_ANSI_K);
    _buttonToKeyMap[@(VBButtonB)]         = @(kVK_ANSI_J);
    
    _buttonToKeyMap[@(VBButtonStart)]     = @(kVK_Return);
    _buttonToKeyMap[@(VBButtonSelect)]    = @(kVK_Shift);
    
    _buttonToKeyMap[@(VBButtonL)]         = @(kVK_ANSI_1);
    _buttonToKeyMap[@(VBButtonR)]         = @(kVK_ANSI_2);
    
    [self rebuildKeyToButtonMap];
}

- (void)loadBindings {
    NSDictionary *saved = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kRedViperKeyBindingsKey];
    
    if (!saved || saved.count == 0) {
        [self resetToDefaults];
        return;
    }
    
    // Convert saved dictionary (string keys) to buttonToKeyMap (NSNumber keys)
    [_buttonToKeyMap removeAllObjects];
    for (NSString *buttonKey in saved) {
        NSNumber *keyCode = saved[buttonKey];
        VBButton button = (VBButton)[buttonKey integerValue];
        if (button >= 0 && button < VBButtonCount && [keyCode isKindOfClass:[NSNumber class]]) {
            _buttonToKeyMap[@(button)] = keyCode;
        }
    }
    
    // Fill in any missing buttons with defaults
    if (_buttonToKeyMap.count < VBButtonCount) {
        // Temporarily store current bindings
        NSDictionary *currentBindings = [_buttonToKeyMap copy];
        [self resetToDefaults];
        // Overlay saved bindings
        [_buttonToKeyMap addEntriesFromDictionary:currentBindings];
    }
    
    [self rebuildKeyToButtonMap];
}

- (void)saveBindings {
    // Convert buttonToKeyMap to dictionary with string keys (for UserDefaults)
    NSMutableDictionary *toSave = [[NSMutableDictionary alloc] init];
    for (NSNumber *buttonNum in _buttonToKeyMap) {
        NSString *buttonKey = [buttonNum stringValue];
        toSave[buttonKey] = _buttonToKeyMap[buttonNum];
    }
    
    [[NSUserDefaults standardUserDefaults] setObject:toSave forKey:kRedViperKeyBindingsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)rebuildKeyToButtonMap {
    [_keyToButtonMap removeAllObjects];
    
    for (NSNumber *buttonNum in _buttonToKeyMap) {
        VBButton button = (VBButton)[buttonNum integerValue];
        NSNumber *keyCode = _buttonToKeyMap[buttonNum];
        uint16_t flag = VBButtonFlags[button];
        _keyToButtonMap[keyCode] = @(flag);
    }
}

- (unsigned short)keyCodeForButton:(VBButton)button {
    NSNumber *keyCode = _buttonToKeyMap[@(button)];
    return keyCode ? [keyCode unsignedShortValue] : 0;
}

- (void)setKeyCode:(unsigned short)keyCode forButton:(VBButton)button {
    _buttonToKeyMap[@(button)] = @(keyCode);
    [self rebuildKeyToButtonMap];
}

+ (NSString *)displayNameForButton:(VBButton)button {
    switch (button) {
        case VBButtonLPadUp:    return @"Left D-Pad Up";
        case VBButtonLPadDown:  return @"Left D-Pad Down";
        case VBButtonLPadLeft:  return @"Left D-Pad Left";
        case VBButtonLPadRight: return @"Left D-Pad Right";
        case VBButtonRPadUp:    return @"Right D-Pad Up";
        case VBButtonRPadDown:  return @"Right D-Pad Down";
        case VBButtonRPadLeft:  return @"Right D-Pad Left";
        case VBButtonRPadRight: return @"Right D-Pad Right";
        case VBButtonA:         return @"A Button";
        case VBButtonB:         return @"B Button";
        case VBButtonStart:     return @"Start";
        case VBButtonSelect:    return @"Select";
        case VBButtonL:         return @"L Trigger";
        case VBButtonR:         return @"R Trigger";
        default:                return @"Unknown";
    }
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
        // Check if this key code is mapped to a button
        NSNumber *buttonFlag = _keyToButtonMap[keyCode];
        if (buttonFlag) {
            result |= [buttonFlag unsignedShortValue];
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
