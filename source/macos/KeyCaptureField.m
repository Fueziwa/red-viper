//
//  KeyCaptureField.m
//  Red Viper - Virtual Boy Emulator for macOS
//
//  Custom NSTextField subclass for press-to-assign key binding capture
//

#import "KeyCaptureField.h"

@implementation KeyCaptureField

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (void)commonInit {
    _capturing = NO;
    _capturedKeyCode = 0;
    [self setEditable:NO];
    [self setSelectable:NO];
    [self setAlignment:NSTextAlignmentCenter];
    [self setBezeled:YES];
    [self setBezelStyle:NSTextFieldSquareBezel];
}

#pragma mark - First Responder

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (BOOL)becomeFirstResponder {
    BOOL result = [super becomeFirstResponder];
    if (result) {
        [self startCapturing];
    }
    return result;
}

- (BOOL)resignFirstResponder {
    if (_capturing) {
        [self cancelCapturing];
    }
    return [super resignFirstResponder];
}

#pragma mark - Capture Control

- (void)startCapturing {
    _capturing = YES;
    [self setStringValue:@"Press a key..."];
}

- (void)cancelCapturing {
    _capturing = NO;
    [self setStringValue:[KeyCaptureField displayNameForKeyCode:_capturedKeyCode]];
}

#pragma mark - Key Handling

- (void)keyDown:(NSEvent *)event {
    if (!_capturing) {
        [super keyDown:event];
        return;
    }
    
    unsigned short keyCode = event.keyCode;
    
    // Check for Cmd modifier - reserved for menu shortcuts
    if (event.modifierFlags & NSEventModifierFlagCommand) {
        NSBeep();
        return;
    }
    
    // Check for reserved keys
    if ([self isReservedKey:keyCode]) {
        NSBeep();
        return;
    }
    
    // Capture the key
    _capturedKeyCode = keyCode;
    _capturing = NO;
    [self setStringValue:[KeyCaptureField displayNameForKeyCode:keyCode]];
    
    // Notify delegate
    if ([self.captureDelegate respondsToSelector:@selector(keyCaptureField:didCaptureKeyCode:)]) {
        [self.captureDelegate keyCaptureField:self didCaptureKeyCode:keyCode];
    }
    
    // Move focus to next field
    [[self window] selectNextKeyView:self];
}

- (void)flagsChanged:(NSEvent *)event {
    if (!_capturing) {
        [super flagsChanged:event];
        return;
    }
    
    // Check for Shift key press
    if (event.modifierFlags & NSEventModifierFlagShift) {
        // Capture Shift as a bindable key
        _capturedKeyCode = kVK_Shift;
        _capturing = NO;
        [self setStringValue:[KeyCaptureField displayNameForKeyCode:kVK_Shift]];
        
        // Notify delegate
        if ([self.captureDelegate respondsToSelector:@selector(keyCaptureField:didCaptureKeyCode:)]) {
            [self.captureDelegate keyCaptureField:self didCaptureKeyCode:kVK_Shift];
        }
        
        // Move focus to next field
        [[self window] selectNextKeyView:self];
    }
}

- (BOOL)isReservedKey:(unsigned short)keyCode {
    // Escape
    if (keyCode == kVK_Escape) {
        return YES;
    }
    
    // Function keys F1-F12
    // F1=0x7A, F2=0x78, F3=0x63, F4=0x76, F5=0x60, F6=0x61
    // F7=0x62, F8=0x64, F9=0x65, F10=0x6D, F11=0x67, F12=0x6F
    switch (keyCode) {
        case kVK_F1:
        case kVK_F2:
        case kVK_F3:
        case kVK_F4:
        case kVK_F5:
        case kVK_F6:
        case kVK_F7:
        case kVK_F8:
        case kVK_F9:
        case kVK_F10:
        case kVK_F11:
        case kVK_F12:
        case kVK_F13:
        case kVK_F14:
        case kVK_F15:
        case kVK_F16:
        case kVK_F17:
        case kVK_F18:
        case kVK_F19:
        case kVK_F20:
            return YES;
    }
    
    return NO;
}

#pragma mark - Key Name Display

+ (NSString *)displayNameForKeyCode:(unsigned short)keyCode {
    static NSDictionary *keyNames = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        keyNames = @{
            // Letters A-Z
            @(kVK_ANSI_A): @"A",
            @(kVK_ANSI_B): @"B",
            @(kVK_ANSI_C): @"C",
            @(kVK_ANSI_D): @"D",
            @(kVK_ANSI_E): @"E",
            @(kVK_ANSI_F): @"F",
            @(kVK_ANSI_G): @"G",
            @(kVK_ANSI_H): @"H",
            @(kVK_ANSI_I): @"I",
            @(kVK_ANSI_J): @"J",
            @(kVK_ANSI_K): @"K",
            @(kVK_ANSI_L): @"L",
            @(kVK_ANSI_M): @"M",
            @(kVK_ANSI_N): @"N",
            @(kVK_ANSI_O): @"O",
            @(kVK_ANSI_P): @"P",
            @(kVK_ANSI_Q): @"Q",
            @(kVK_ANSI_R): @"R",
            @(kVK_ANSI_S): @"S",
            @(kVK_ANSI_T): @"T",
            @(kVK_ANSI_U): @"U",
            @(kVK_ANSI_V): @"V",
            @(kVK_ANSI_W): @"W",
            @(kVK_ANSI_X): @"X",
            @(kVK_ANSI_Y): @"Y",
            @(kVK_ANSI_Z): @"Z",
            
            // Numbers 0-9
            @(kVK_ANSI_0): @"0",
            @(kVK_ANSI_1): @"1",
            @(kVK_ANSI_2): @"2",
            @(kVK_ANSI_3): @"3",
            @(kVK_ANSI_4): @"4",
            @(kVK_ANSI_5): @"5",
            @(kVK_ANSI_6): @"6",
            @(kVK_ANSI_7): @"7",
            @(kVK_ANSI_8): @"8",
            @(kVK_ANSI_9): @"9",
            
            // Punctuation
            @(kVK_ANSI_Semicolon): @";",
            @(kVK_ANSI_Quote): @"'",
            @(kVK_ANSI_Comma): @",",
            @(kVK_ANSI_Period): @".",
            @(kVK_ANSI_Slash): @"/",
            @(kVK_ANSI_Backslash): @"\\",
            @(kVK_ANSI_LeftBracket): @"[",
            @(kVK_ANSI_RightBracket): @"]",
            @(kVK_ANSI_Minus): @"-",
            @(kVK_ANSI_Equal): @"=",
            @(kVK_ANSI_Grave): @"`",
            
            // Special keys
            @(kVK_Return): @"Return",
            @(kVK_Space): @"Space",
            @(kVK_Tab): @"Tab",
            @(kVK_Delete): @"Delete",
            @(kVK_ForwardDelete): @"Fwd Delete",
            @(kVK_Escape): @"Escape",
            
            // Arrow keys
            @(kVK_UpArrow): @"Up",
            @(kVK_DownArrow): @"Down",
            @(kVK_LeftArrow): @"Left",
            @(kVK_RightArrow): @"Right",
            
            // Modifiers
            @(kVK_Shift): @"Shift",
            @(kVK_RightShift): @"Right Shift",
            @(kVK_Control): @"Control",
            @(kVK_RightControl): @"Right Control",
            @(kVK_Option): @"Option",
            @(kVK_RightOption): @"Right Option",
            @(kVK_Command): @"Command",
            @(kVK_RightCommand): @"Right Command",
            @(kVK_CapsLock): @"Caps Lock",
            @(kVK_Function): @"Fn",
            
            // Keypad
            @(kVK_ANSI_Keypad0): @"Keypad 0",
            @(kVK_ANSI_Keypad1): @"Keypad 1",
            @(kVK_ANSI_Keypad2): @"Keypad 2",
            @(kVK_ANSI_Keypad3): @"Keypad 3",
            @(kVK_ANSI_Keypad4): @"Keypad 4",
            @(kVK_ANSI_Keypad5): @"Keypad 5",
            @(kVK_ANSI_Keypad6): @"Keypad 6",
            @(kVK_ANSI_Keypad7): @"Keypad 7",
            @(kVK_ANSI_Keypad8): @"Keypad 8",
            @(kVK_ANSI_Keypad9): @"Keypad 9",
            @(kVK_ANSI_KeypadDecimal): @"Keypad .",
            @(kVK_ANSI_KeypadMultiply): @"Keypad *",
            @(kVK_ANSI_KeypadPlus): @"Keypad +",
            @(kVK_ANSI_KeypadMinus): @"Keypad -",
            @(kVK_ANSI_KeypadDivide): @"Keypad /",
            @(kVK_ANSI_KeypadEnter): @"Keypad Enter",
            @(kVK_ANSI_KeypadEquals): @"Keypad =",
            @(kVK_ANSI_KeypadClear): @"Keypad Clear",
            
            // Navigation
            @(kVK_Home): @"Home",
            @(kVK_End): @"End",
            @(kVK_PageUp): @"Page Up",
            @(kVK_PageDown): @"Page Down",
            @(kVK_Help): @"Help",
        };
    });
    
    NSString *name = keyNames[@(keyCode)];
    if (name) {
        return name;
    }
    
    return [NSString stringWithFormat:@"Key %d", keyCode];
}

#pragma mark - Mouse Handling

- (void)mouseDown:(NSEvent *)event {
    // When clicked, become first responder to start capturing
    [[self window] makeFirstResponder:self];
}

@end
