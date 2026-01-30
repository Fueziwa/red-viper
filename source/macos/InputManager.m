//
//  InputManager.m
//  Red Viper - Virtual Boy Emulator for macOS
//
//  Singleton class for keyboard and gamepad input handling with Virtual Boy button mapping
//

#import "InputManager.h"
#include "vb_dsp.h"

/// UserDefaults key for storing key bindings
static NSString * const kRedViperKeyBindingsKey = @"RedViperKeyBindings";

/// UserDefaults key for storing gamepad bindings
static NSString * const kRedViperGamepadBindingsKey = @"RedViperGamepadBindings";

/// Analog stick threshold for d-pad activation (0.5 = halfway deflection)
static const float kAnalogStickThreshold = 0.5f;

/// Analog trigger threshold for button activation (lower than stick since triggers have more travel)
static const float kAnalogTriggerThreshold = 0.25f;

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
    
    /// Currently active game controller
    GCController *_activeController;
    
    /// Maps GamepadButton (NSNumber) -> VBButton (NSNumber)
    NSMutableDictionary<NSNumber *, NSNumber *> *_gamepadToVBButtonMap;
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
        _gamepadToVBButtonMap = [[NSMutableDictionary alloc] init];
        _activeController = nil;
        
        [self loadBindings];
        [self loadGamepadBindings];
        
        // Register for controller connect/disconnect notifications
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(controllerDidConnect:)
                                                     name:GCControllerDidConnectNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(controllerDidDisconnect:)
                                                     name:GCControllerDidDisconnectNotification
                                                   object:nil];
        
        // Check for already-connected controllers
        [self checkForExistingControllers];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
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

#pragma mark - Gamepad Binding Customization

- (void)resetGamepadBindingsToDefaults {
    [_gamepadToVBButtonMap removeAllObjects];
    
    // Per CONTEXT.md: A = right face (B on Xbox), B = bottom face (A on Xbox)
    _gamepadToVBButtonMap[@(GamepadButtonB)] = @(VBButtonA);  // Xbox B -> VB A
    _gamepadToVBButtonMap[@(GamepadButtonA)] = @(VBButtonB);  // Xbox A -> VB B
    
    // D-pad -> Left D-Pad
    _gamepadToVBButtonMap[@(GamepadButtonDpadUp)] = @(VBButtonLPadUp);
    _gamepadToVBButtonMap[@(GamepadButtonDpadDown)] = @(VBButtonLPadDown);
    _gamepadToVBButtonMap[@(GamepadButtonDpadLeft)] = @(VBButtonLPadLeft);
    _gamepadToVBButtonMap[@(GamepadButtonDpadRight)] = @(VBButtonLPadRight);
    
    // Left stick -> Left D-Pad
    _gamepadToVBButtonMap[@(GamepadButtonLeftStickUp)] = @(VBButtonLPadUp);
    _gamepadToVBButtonMap[@(GamepadButtonLeftStickDown)] = @(VBButtonLPadDown);
    _gamepadToVBButtonMap[@(GamepadButtonLeftStickLeft)] = @(VBButtonLPadLeft);
    _gamepadToVBButtonMap[@(GamepadButtonLeftStickRight)] = @(VBButtonLPadRight);
    
    // Right stick -> Right D-Pad
    _gamepadToVBButtonMap[@(GamepadButtonRightStickUp)] = @(VBButtonRPadUp);
    _gamepadToVBButtonMap[@(GamepadButtonRightStickDown)] = @(VBButtonRPadDown);
    _gamepadToVBButtonMap[@(GamepadButtonRightStickLeft)] = @(VBButtonRPadLeft);
    _gamepadToVBButtonMap[@(GamepadButtonRightStickRight)] = @(VBButtonRPadRight);
    
    // Triggers/Shoulders -> L/R
    _gamepadToVBButtonMap[@(GamepadButtonLeftShoulder)] = @(VBButtonL);
    _gamepadToVBButtonMap[@(GamepadButtonLeftTrigger)] = @(VBButtonL);
    _gamepadToVBButtonMap[@(GamepadButtonRightShoulder)] = @(VBButtonR);
    _gamepadToVBButtonMap[@(GamepadButtonRightTrigger)] = @(VBButtonR);
    
    // Start/Select
    _gamepadToVBButtonMap[@(GamepadButtonMenu)] = @(VBButtonStart);
    _gamepadToVBButtonMap[@(GamepadButtonOptions)] = @(VBButtonSelect);
}

- (void)loadGamepadBindings {
    NSDictionary *saved = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kRedViperGamepadBindingsKey];
    
    if (!saved || saved.count == 0) {
        [self resetGamepadBindingsToDefaults];
        return;
    }
    
    // Convert saved dictionary (string keys) to gamepadToVBButtonMap (NSNumber keys)
    [_gamepadToVBButtonMap removeAllObjects];
    for (NSString *buttonKey in saved) {
        NSNumber *vbButton = saved[buttonKey];
        GamepadButton gpButton = (GamepadButton)[buttonKey integerValue];
        if (gpButton >= 0 && gpButton < GamepadButtonCount && [vbButton isKindOfClass:[NSNumber class]]) {
            _gamepadToVBButtonMap[@(gpButton)] = vbButton;
        }
    }
    
    // If nothing was loaded, reset to defaults
    if (_gamepadToVBButtonMap.count == 0) {
        [self resetGamepadBindingsToDefaults];
    }
}

- (void)saveGamepadBindings {
    // Convert gamepadToVBButtonMap to dictionary with string keys (for UserDefaults)
    NSMutableDictionary *toSave = [[NSMutableDictionary alloc] init];
    for (NSNumber *gpButtonNum in _gamepadToVBButtonMap) {
        NSString *buttonKey = [gpButtonNum stringValue];
        toSave[buttonKey] = _gamepadToVBButtonMap[gpButtonNum];
    }
    
    [[NSUserDefaults standardUserDefaults] setObject:toSave forKey:kRedViperGamepadBindingsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (VBButton)vbButtonForGamepadButton:(GamepadButton)gamepadButton {
    NSNumber *vbButtonNum = _gamepadToVBButtonMap[@(gamepadButton)];
    if (vbButtonNum) {
        return (VBButton)[vbButtonNum integerValue];
    }
    return VBButtonCount;  // Unmapped
}

- (void)setVBButton:(VBButton)vbButton forGamepadButton:(GamepadButton)gamepadButton {
    if (vbButton == VBButtonCount) {
        // Unmap this gamepad button
        [_gamepadToVBButtonMap removeObjectForKey:@(gamepadButton)];
    } else {
        _gamepadToVBButtonMap[@(gamepadButton)] = @(vbButton);
    }
}

+ (NSString *)displayNameForGamepadButton:(GamepadButton)gamepadButton {
    switch (gamepadButton) {
        case GamepadButtonA:               return @"A Button";
        case GamepadButtonB:               return @"B Button";
        case GamepadButtonX:               return @"X Button";
        case GamepadButtonY:               return @"Y Button";
        case GamepadButtonLeftShoulder:    return @"Left Shoulder";
        case GamepadButtonRightShoulder:   return @"Right Shoulder";
        case GamepadButtonLeftTrigger:     return @"Left Trigger";
        case GamepadButtonRightTrigger:    return @"Right Trigger";
        case GamepadButtonDpadUp:          return @"D-Pad Up";
        case GamepadButtonDpadDown:        return @"D-Pad Down";
        case GamepadButtonDpadLeft:        return @"D-Pad Left";
        case GamepadButtonDpadRight:       return @"D-Pad Right";
        case GamepadButtonLeftStickUp:     return @"Left Stick Up";
        case GamepadButtonLeftStickDown:   return @"Left Stick Down";
        case GamepadButtonLeftStickLeft:   return @"Left Stick Left";
        case GamepadButtonLeftStickRight:  return @"Left Stick Right";
        case GamepadButtonRightStickUp:    return @"Right Stick Up";
        case GamepadButtonRightStickDown:  return @"Right Stick Down";
        case GamepadButtonRightStickLeft:  return @"Right Stick Left";
        case GamepadButtonRightStickRight: return @"Right Stick Right";
        case GamepadButtonMenu:            return @"Menu";
        case GamepadButtonOptions:         return @"Options";
        default:                           return @"Unknown";
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
    
    // Per CONTEXT.md: Gamepad overrides keyboard when connected
    if ([self isGamepadActive]) {
        result |= [self pollGamepadState];
        return result;
    }
    
    // Fall back to keyboard input
    for (NSNumber *keyCode in _pressedKeys) {
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

#pragma mark - Gamepad Support

- (GCController *)activeController {
    return _activeController;
}

- (void)checkForExistingControllers {
    for (GCController *controller in [GCController controllers]) {
        if (controller.extendedGamepad) {
            _activeController = controller;
            _activeController.playerIndex = GCControllerPlayerIndex1;
            NSLog(@"InputManager: Found existing controller: %@", controller.vendorName);
            break;
        }
    }
}

- (void)controllerDidConnect:(NSNotification *)notification {
    GCController *controller = notification.object;
    
    // Only use controllers with extended gamepad profile
    if (!controller.extendedGamepad) {
        NSLog(@"InputManager: Ignoring controller without extended gamepad: %@", controller.vendorName);
        return;
    }
    
    // First controller wins (per CONTEXT.md decision)
    if (_activeController == nil) {
        _activeController = controller;
        _activeController.playerIndex = GCControllerPlayerIndex1;
        NSLog(@"InputManager: Controller connected: %@", controller.vendorName);
    }
}

- (void)controllerDidDisconnect:(NSNotification *)notification {
    GCController *controller = notification.object;
    
    if (controller == _activeController) {
        NSLog(@"InputManager: Controller disconnected: %@", controller.vendorName);
        _activeController = nil;
        
        // Try to find another connected controller
        [self checkForExistingControllers];
    }
}

- (BOOL)isGamepadActive {
    return _activeController != nil && _activeController.extendedGamepad != nil;
}

- (uint16_t)pollGamepadState {
    GCExtendedGamepad *gp = _activeController.extendedGamepad;
    if (!gp) {
        return 0;
    }
    
    __block uint16_t result = 0;
    
    // Helper block to add VB button flag if gamepad button is mapped
    void (^addIfMapped)(GamepadButton) = ^(GamepadButton gpButton) {
        NSNumber *vbButtonNum = self->_gamepadToVBButtonMap[@(gpButton)];
        if (vbButtonNum) {
            VBButton vbButton = (VBButton)[vbButtonNum integerValue];
            if (vbButton < VBButtonCount) {
                result |= VBButtonFlags[vbButton];
            }
        }
    };
    
    // Face buttons
    if (gp.buttonA.isPressed) addIfMapped(GamepadButtonA);
    if (gp.buttonB.isPressed) addIfMapped(GamepadButtonB);
    if (gp.buttonX.isPressed) addIfMapped(GamepadButtonX);
    if (gp.buttonY.isPressed) addIfMapped(GamepadButtonY);
    
    // Shoulders
    if (gp.leftShoulder.isPressed)  addIfMapped(GamepadButtonLeftShoulder);
    if (gp.rightShoulder.isPressed) addIfMapped(GamepadButtonRightShoulder);
    
    // Triggers (with analog threshold)
    if (gp.leftTrigger.value > kAnalogTriggerThreshold)  addIfMapped(GamepadButtonLeftTrigger);
    if (gp.rightTrigger.value > kAnalogTriggerThreshold) addIfMapped(GamepadButtonRightTrigger);
    
    // Menu buttons
    if (gp.buttonMenu.isPressed)    addIfMapped(GamepadButtonMenu);
    if (gp.buttonOptions.isPressed) addIfMapped(GamepadButtonOptions);
    
    // D-Pad
    if (gp.dpad.up.isPressed)    addIfMapped(GamepadButtonDpadUp);
    if (gp.dpad.down.isPressed)  addIfMapped(GamepadButtonDpadDown);
    if (gp.dpad.left.isPressed)  addIfMapped(GamepadButtonDpadLeft);
    if (gp.dpad.right.isPressed) addIfMapped(GamepadButtonDpadRight);
    
    // Left stick (with analog threshold)
    if (gp.leftThumbstick.yAxis.value > kAnalogStickThreshold)  addIfMapped(GamepadButtonLeftStickUp);
    if (gp.leftThumbstick.yAxis.value < -kAnalogStickThreshold) addIfMapped(GamepadButtonLeftStickDown);
    if (gp.leftThumbstick.xAxis.value < -kAnalogStickThreshold) addIfMapped(GamepadButtonLeftStickLeft);
    if (gp.leftThumbstick.xAxis.value > kAnalogStickThreshold)  addIfMapped(GamepadButtonLeftStickRight);
    
    // Right stick (with analog threshold)
    if (gp.rightThumbstick.yAxis.value > kAnalogStickThreshold)  addIfMapped(GamepadButtonRightStickUp);
    if (gp.rightThumbstick.yAxis.value < -kAnalogStickThreshold) addIfMapped(GamepadButtonRightStickDown);
    if (gp.rightThumbstick.xAxis.value < -kAnalogStickThreshold) addIfMapped(GamepadButtonRightStickLeft);
    if (gp.rightThumbstick.xAxis.value > kAnalogStickThreshold)  addIfMapped(GamepadButtonRightStickRight);
    
    return result;
}

@end

#pragma mark - C-Callable Function

uint16_t InputManager_currentControllerState(void) {
    return [[InputManager sharedManager] currentControllerState];
}
