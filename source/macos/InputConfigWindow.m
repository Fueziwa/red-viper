//
//  InputConfigWindow.m
//  Red Viper - Virtual Boy Emulator for macOS
//
//  Standalone window controller for keyboard and gamepad input configuration
//

#import "InputConfigWindow.h"
#import "KeyCaptureField.h"
#import "InputManager.h"

/// Window dimensions
static const CGFloat kWindowWidth = 600.0;
static const CGFloat kWindowHeight = 520.0;
static const CGFloat kMargin = 20.0;
static const CGFloat kRowHeight = 28.0;
static const CGFloat kLabelWidth = 140.0;
static const CGFloat kFieldWidth = 120.0;
static const CGFloat kPopupWidth = 160.0;

/// Shared instance
static InputConfigWindow *sharedInstance = nil;

@interface InputConfigWindow () <NSWindowDelegate, KeyCaptureFieldDelegate>
@end

@implementation InputConfigWindow {
    NSTabView *_tabView;
    
    // Keyboard tab
    NSMutableArray<KeyCaptureField *> *_keyCaptureFields;
    NSMutableDictionary<NSNumber *, NSNumber *> *_pendingKeyBindings;
    
    // Gamepad tab
    NSMutableArray<NSPopUpButton *> *_gamepadPopups;  // One per VBButton
    NSMutableDictionary<NSNumber *, NSNumber *> *_pendingGamepadBindings;  // GamepadButton -> VBButton
}

#pragma mark - Singleton

+ (void)showWindow {
    if (!sharedInstance) {
        sharedInstance = [[InputConfigWindow alloc] init];
    }
    [sharedInstance.window makeKeyAndOrderFront:nil];
    [sharedInstance.window center];
    [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
}

#pragma mark - Initialization

- (instancetype)init {
    // Create window programmatically
    NSRect frame = NSMakeRect(0, 0, kWindowWidth, kWindowHeight);
    NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable;
    
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:style
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    [window setTitle:@"Input Configuration"];
    [window setDelegate:self];
    
    self = [super initWithWindow:window];
    if (self) {
        _keyCaptureFields = [[NSMutableArray alloc] init];
        _pendingKeyBindings = [[NSMutableDictionary alloc] init];
        _gamepadPopups = [[NSMutableArray alloc] init];
        _pendingGamepadBindings = [[NSMutableDictionary alloc] init];
        
        [self buildWindowContents];
        [self loadCurrentBindings];
    }
    return self;
}

#pragma mark - Window Content

- (void)buildWindowContents {
    NSView *contentView = [self.window contentView];
    
    // Create tab view
    NSRect tabFrame = NSMakeRect(kMargin, 60, kWindowWidth - kMargin * 2, kWindowHeight - 80);
    _tabView = [[NSTabView alloc] initWithFrame:tabFrame];
    [_tabView setTabViewType:NSTopTabsBezelBorder];
    [contentView addSubview:_tabView];
    
    // Create tabs
    [self createKeyboardTab];
    [self createGamepadTab];
    
    // Bottom buttons
    CGFloat buttonY = kMargin;
    CGFloat buttonWidth = 100;
    CGFloat buttonHeight = 32;
    
    // OK button (right)
    NSButton *okButton = [[NSButton alloc] initWithFrame:NSMakeRect(kWindowWidth - kMargin - buttonWidth, buttonY, buttonWidth, buttonHeight)];
    [okButton setTitle:@"OK"];
    [okButton setBezelStyle:NSBezelStyleRounded];
    [okButton setKeyEquivalent:@"\r"];
    [okButton setTarget:self];
    [okButton setAction:@selector(okPressed:)];
    [contentView addSubview:okButton];
    
    // Cancel button (left of OK)
    NSButton *cancelButton = [[NSButton alloc] initWithFrame:NSMakeRect(kWindowWidth - kMargin - buttonWidth * 2 - 10, buttonY, buttonWidth, buttonHeight)];
    [cancelButton setTitle:@"Cancel"];
    [cancelButton setBezelStyle:NSBezelStyleRounded];
    [cancelButton setKeyEquivalent:@"\033"];
    [cancelButton setTarget:self];
    [cancelButton setAction:@selector(cancelPressed:)];
    [contentView addSubview:cancelButton];
}

#pragma mark - Keyboard Tab

- (void)createKeyboardTab {
    NSTabViewItem *keyboardItem = [[NSTabViewItem alloc] initWithIdentifier:@"keyboard"];
    [keyboardItem setLabel:@"Keyboard"];
    
    NSView *keyboardView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kWindowWidth - kMargin * 2 - 10, kWindowHeight - 140)];
    [keyboardItem setView:keyboardView];
    
    CGFloat leftColumnX = 10;
    CGFloat rightColumnX = (kWindowWidth - kMargin * 2) / 2;
    CGFloat startY = keyboardView.frame.size.height - 40;
    
    // Left column: Left D-Pad
    [self addSectionLabel:@"Left D-Pad" atX:leftColumnX y:startY toView:keyboardView];
    CGFloat y = startY - kRowHeight;
    y = [self addKeyboardRow:VBButtonLPadUp    atX:leftColumnX y:y toView:keyboardView];
    y = [self addKeyboardRow:VBButtonLPadDown  atX:leftColumnX y:y toView:keyboardView];
    y = [self addKeyboardRow:VBButtonLPadLeft  atX:leftColumnX y:y toView:keyboardView];
    y = [self addKeyboardRow:VBButtonLPadRight atX:leftColumnX y:y toView:keyboardView];
    
    // Left column: Action buttons
    y -= 10;
    [self addSectionLabel:@"Buttons" atX:leftColumnX y:y toView:keyboardView];
    y -= kRowHeight;
    y = [self addKeyboardRow:VBButtonA atX:leftColumnX y:y toView:keyboardView];
    y = [self addKeyboardRow:VBButtonB atX:leftColumnX y:y toView:keyboardView];
    
    // Left column: Start/Select
    y -= 10;
    [self addSectionLabel:@"System" atX:leftColumnX y:y toView:keyboardView];
    y -= kRowHeight;
    y = [self addKeyboardRow:VBButtonStart  atX:leftColumnX y:y toView:keyboardView];
    y = [self addKeyboardRow:VBButtonSelect atX:leftColumnX y:y toView:keyboardView];
    
    // Right column: Right D-Pad
    y = startY;
    [self addSectionLabel:@"Right D-Pad" atX:rightColumnX y:y toView:keyboardView];
    y -= kRowHeight;
    y = [self addKeyboardRow:VBButtonRPadUp    atX:rightColumnX y:y toView:keyboardView];
    y = [self addKeyboardRow:VBButtonRPadDown  atX:rightColumnX y:y toView:keyboardView];
    y = [self addKeyboardRow:VBButtonRPadLeft  atX:rightColumnX y:y toView:keyboardView];
    y = [self addKeyboardRow:VBButtonRPadRight atX:rightColumnX y:y toView:keyboardView];
    
    // Right column: Triggers
    y -= 10;
    [self addSectionLabel:@"Triggers" atX:rightColumnX y:y toView:keyboardView];
    y -= kRowHeight;
    y = [self addKeyboardRow:VBButtonL atX:rightColumnX y:y toView:keyboardView];
    y = [self addKeyboardRow:VBButtonR atX:rightColumnX y:y toView:keyboardView];
    
    // Reset to Defaults button
    CGFloat resetY = 10;
    NSButton *resetButton = [[NSButton alloc] initWithFrame:NSMakeRect(10, resetY, 150, 28)];
    [resetButton setTitle:@"Reset to Defaults"];
    [resetButton setBezelStyle:NSBezelStyleRounded];
    [resetButton setTarget:self];
    [resetButton setAction:@selector(resetKeyboardToDefaults:)];
    [keyboardView addSubview:resetButton];
    
    [_tabView addTabViewItem:keyboardItem];
}

- (CGFloat)addKeyboardRow:(VBButton)button atX:(CGFloat)x y:(CGFloat)y toView:(NSView *)view {
    // Label
    NSString *buttonName = [InputManager displayNameForButton:button];
    NSTextField *label = [self createLabelWithText:buttonName];
    [label setFrame:NSMakeRect(x, y, kLabelWidth, 22)];
    [view addSubview:label];
    
    // Key capture field
    KeyCaptureField *field = [[KeyCaptureField alloc] initWithFrame:NSMakeRect(x + kLabelWidth + 5, y, kFieldWidth, 22)];
    [field setBordered:YES];
    [field setBezeled:YES];
    [field setBezelStyle:NSTextFieldRoundedBezel];
    [field setEditable:NO];
    [field setCaptureDelegate:self];
    
    // Store at the correct index
    while (_keyCaptureFields.count <= button) {
        [_keyCaptureFields addObject:[[KeyCaptureField alloc] init]];
    }
    _keyCaptureFields[button] = field;
    
    [view addSubview:field];
    
    return y - kRowHeight;
}

#pragma mark - Gamepad Tab

- (void)createGamepadTab {
    NSTabViewItem *gamepadItem = [[NSTabViewItem alloc] initWithIdentifier:@"gamepad"];
    [gamepadItem setLabel:@"Gamepad"];
    
    NSView *gamepadView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kWindowWidth - kMargin * 2 - 10, kWindowHeight - 140)];
    [gamepadItem setView:gamepadView];
    
    CGFloat leftColumnX = 10;
    CGFloat rightColumnX = (kWindowWidth - kMargin * 2) / 2;
    CGFloat startY = gamepadView.frame.size.height - 40;
    
    // Left column: Left D-Pad
    [self addSectionLabel:@"Left D-Pad" atX:leftColumnX y:startY toView:gamepadView];
    CGFloat y = startY - kRowHeight;
    y = [self addGamepadRow:VBButtonLPadUp    atX:leftColumnX y:y toView:gamepadView];
    y = [self addGamepadRow:VBButtonLPadDown  atX:leftColumnX y:y toView:gamepadView];
    y = [self addGamepadRow:VBButtonLPadLeft  atX:leftColumnX y:y toView:gamepadView];
    y = [self addGamepadRow:VBButtonLPadRight atX:leftColumnX y:y toView:gamepadView];
    
    // Left column: Action buttons
    y -= 10;
    [self addSectionLabel:@"Buttons" atX:leftColumnX y:y toView:gamepadView];
    y -= kRowHeight;
    y = [self addGamepadRow:VBButtonA atX:leftColumnX y:y toView:gamepadView];
    y = [self addGamepadRow:VBButtonB atX:leftColumnX y:y toView:gamepadView];
    
    // Left column: Start/Select
    y -= 10;
    [self addSectionLabel:@"System" atX:leftColumnX y:y toView:gamepadView];
    y -= kRowHeight;
    y = [self addGamepadRow:VBButtonStart  atX:leftColumnX y:y toView:gamepadView];
    y = [self addGamepadRow:VBButtonSelect atX:leftColumnX y:y toView:gamepadView];
    
    // Right column: Right D-Pad
    y = startY;
    [self addSectionLabel:@"Right D-Pad" atX:rightColumnX y:y toView:gamepadView];
    y -= kRowHeight;
    y = [self addGamepadRow:VBButtonRPadUp    atX:rightColumnX y:y toView:gamepadView];
    y = [self addGamepadRow:VBButtonRPadDown  atX:rightColumnX y:y toView:gamepadView];
    y = [self addGamepadRow:VBButtonRPadLeft  atX:rightColumnX y:y toView:gamepadView];
    y = [self addGamepadRow:VBButtonRPadRight atX:rightColumnX y:y toView:gamepadView];
    
    // Right column: Triggers
    y -= 10;
    [self addSectionLabel:@"Triggers" atX:rightColumnX y:y toView:gamepadView];
    y -= kRowHeight;
    y = [self addGamepadRow:VBButtonL atX:rightColumnX y:y toView:gamepadView];
    y = [self addGamepadRow:VBButtonR atX:rightColumnX y:y toView:gamepadView];
    
    // Reset to Defaults button
    CGFloat resetY = 10;
    NSButton *resetButton = [[NSButton alloc] initWithFrame:NSMakeRect(10, resetY, 150, 28)];
    [resetButton setTitle:@"Reset to Defaults"];
    [resetButton setBezelStyle:NSBezelStyleRounded];
    [resetButton setTarget:self];
    [resetButton setAction:@selector(resetGamepadToDefaults:)];
    [gamepadView addSubview:resetButton];
    
    [_tabView addTabViewItem:gamepadItem];
}

- (CGFloat)addGamepadRow:(VBButton)vbButton atX:(CGFloat)x y:(CGFloat)y toView:(NSView *)view {
    // Label
    NSString *buttonName = [InputManager displayNameForButton:vbButton];
    NSTextField *label = [self createLabelWithText:buttonName];
    [label setFrame:NSMakeRect(x, y, kLabelWidth, 22)];
    [view addSubview:label];
    
    // Popup button for gamepad button selection
    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(x + kLabelWidth + 5, y, kPopupWidth, 22) pullsDown:NO];
    [popup setTarget:self];
    [popup setAction:@selector(gamepadPopupChanged:)];
    [popup setTag:vbButton];  // Store VBButton in tag
    
    // Add "None" option
    [popup addItemWithTitle:@"None"];
    [[popup lastItem] setTag:-1];
    
    // Add separator
    [[popup menu] addItem:[NSMenuItem separatorItem]];
    
    // Add all gamepad buttons
    for (NSInteger gpButton = 0; gpButton < GamepadButtonCount; gpButton++) {
        NSString *gpName = [InputManager displayNameForGamepadButton:(GamepadButton)gpButton];
        [popup addItemWithTitle:gpName];
        [[popup lastItem] setTag:gpButton];
    }
    
    // Store at the correct index
    while (_gamepadPopups.count <= vbButton) {
        [_gamepadPopups addObject:[[NSPopUpButton alloc] init]];
    }
    _gamepadPopups[vbButton] = popup;
    
    [view addSubview:popup];
    
    return y - kRowHeight;
}

#pragma mark - Helper Methods

- (void)addSectionLabel:(NSString *)text atX:(CGFloat)x y:(CGFloat)y toView:(NSView *)view {
    NSTextField *label = [self createLabelWithText:text];
    [label setFont:[NSFont boldSystemFontOfSize:12]];
    [label setFrame:NSMakeRect(x, y, kLabelWidth + kFieldWidth, 20)];
    [view addSubview:label];
}

- (NSTextField *)createLabelWithText:(NSString *)text {
    NSTextField *label = [[NSTextField alloc] init];
    [label setStringValue:text];
    [label setBezeled:NO];
    [label setDrawsBackground:NO];
    [label setEditable:NO];
    [label setSelectable:NO];
    return label;
}

#pragma mark - Load/Save Bindings

- (void)loadCurrentBindings {
    // Load keyboard bindings
    [_pendingKeyBindings removeAllObjects];
    for (NSInteger i = 0; i < VBButtonCount; i++) {
        unsigned short keyCode = [[InputManager sharedManager] keyCodeForButton:(VBButton)i];
        _pendingKeyBindings[@(i)] = @(keyCode);
        
        if (i < (NSInteger)_keyCaptureFields.count) {
            KeyCaptureField *field = _keyCaptureFields[i];
            [field setCapturedKeyCode:keyCode];
            [field setStringValue:[KeyCaptureField displayNameForKeyCode:keyCode]];
        }
    }
    
    // Load gamepad bindings - need to find which gamepad button maps to each VB button
    [_pendingGamepadBindings removeAllObjects];
    
    // Copy current bindings
    for (NSInteger gpButton = 0; gpButton < GamepadButtonCount; gpButton++) {
        VBButton vbButton = [[InputManager sharedManager] vbButtonForGamepadButton:(GamepadButton)gpButton];
        if (vbButton < VBButtonCount) {
            _pendingGamepadBindings[@(gpButton)] = @(vbButton);
        }
    }
    
    // Update popup selections
    [self updateGamepadPopupsFromPendingBindings];
}

- (void)updateGamepadPopupsFromPendingBindings {
    // For each VB button, find which gamepad button maps to it
    for (NSInteger vbButton = 0; vbButton < VBButtonCount && vbButton < (NSInteger)_gamepadPopups.count; vbButton++) {
        NSPopUpButton *popup = _gamepadPopups[vbButton];
        
        // Find the first gamepad button that maps to this VB button
        GamepadButton foundGpButton = GamepadButtonCount;
        for (NSInteger gpButton = 0; gpButton < GamepadButtonCount; gpButton++) {
            NSNumber *mappedVB = _pendingGamepadBindings[@(gpButton)];
            if (mappedVB && [mappedVB integerValue] == vbButton) {
                foundGpButton = (GamepadButton)gpButton;
                break;
            }
        }
        
        if (foundGpButton < GamepadButtonCount) {
            [popup selectItemWithTag:foundGpButton];
        } else {
            [popup selectItemWithTag:-1];  // None
        }
    }
}

#pragma mark - KeyCaptureFieldDelegate

- (void)keyCaptureField:(KeyCaptureField *)field didCaptureKeyCode:(unsigned short)keyCode {
    NSUInteger index = [_keyCaptureFields indexOfObject:field];
    if (index == NSNotFound || index >= VBButtonCount) {
        return;
    }
    
    VBButton button = (VBButton)index;
    _pendingKeyBindings[@(button)] = @(keyCode);
    [field setStringValue:[KeyCaptureField displayNameForKeyCode:keyCode]];
}

#pragma mark - Gamepad Popup Changed

- (void)gamepadPopupChanged:(NSPopUpButton *)sender {
    VBButton vbButton = (VBButton)sender.tag;
    GamepadButton gpButton = (GamepadButton)[[sender selectedItem] tag];
    
    // If "None" selected, remove any mapping to this VB button
    if (gpButton < 0) {
        // Find and remove gamepad buttons that map to this VB button
        NSMutableArray *keysToRemove = [[NSMutableArray alloc] init];
        for (NSNumber *key in _pendingGamepadBindings) {
            if ([_pendingGamepadBindings[key] integerValue] == vbButton) {
                [keysToRemove addObject:key];
            }
        }
        for (NSNumber *key in keysToRemove) {
            [_pendingGamepadBindings removeObjectForKey:key];
        }
    } else {
        // First, remove any existing mapping for this gamepad button
        [_pendingGamepadBindings removeObjectForKey:@(gpButton)];
        
        // Also remove any other gamepad button that was mapping to this VB button
        // (to prevent duplicate mappings for the same VB button from the same gamepad source)
        NSMutableArray *keysToRemove = [[NSMutableArray alloc] init];
        for (NSNumber *key in _pendingGamepadBindings) {
            if ([_pendingGamepadBindings[key] integerValue] == vbButton) {
                [keysToRemove addObject:key];
            }
        }
        for (NSNumber *key in keysToRemove) {
            [_pendingGamepadBindings removeObjectForKey:key];
        }
        
        // Set the new mapping
        _pendingGamepadBindings[@(gpButton)] = @(vbButton);
    }
}

#pragma mark - Button Actions

- (void)okPressed:(id)sender {
    // Apply keyboard bindings
    for (NSNumber *buttonNum in _pendingKeyBindings) {
        VBButton button = (VBButton)[buttonNum integerValue];
        unsigned short keyCode = [_pendingKeyBindings[buttonNum] unsignedShortValue];
        [[InputManager sharedManager] setKeyCode:keyCode forButton:button];
    }
    [[InputManager sharedManager] saveBindings];
    
    // Apply gamepad bindings
    // First reset to clear all, then set from pending
    [[InputManager sharedManager] resetGamepadBindingsToDefaults];
    
    // Clear all first
    for (NSInteger gpButton = 0; gpButton < GamepadButtonCount; gpButton++) {
        [[InputManager sharedManager] setVBButton:VBButtonCount forGamepadButton:(GamepadButton)gpButton];
    }
    
    // Apply pending bindings
    for (NSNumber *gpButtonNum in _pendingGamepadBindings) {
        GamepadButton gpButton = (GamepadButton)[gpButtonNum integerValue];
        VBButton vbButton = (VBButton)[_pendingGamepadBindings[gpButtonNum] integerValue];
        [[InputManager sharedManager] setVBButton:vbButton forGamepadButton:gpButton];
    }
    [[InputManager sharedManager] saveGamepadBindings];
    
    [self.window close];
}

- (void)cancelPressed:(id)sender {
    [self.window close];
}

- (void)resetKeyboardToDefaults:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"Reset Keyboard Bindings"];
    [alert setInformativeText:@"Reset all keyboard bindings to their default values?"];
    [alert setAlertStyle:NSAlertStyleWarning];
    [alert addButtonWithTitle:@"Reset"];
    [alert addButtonWithTitle:@"Cancel"];
    
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            [[InputManager sharedManager] resetToDefaults];
            [self loadCurrentBindings];
        }
    }];
}

- (void)resetGamepadToDefaults:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"Reset Gamepad Bindings"];
    [alert setInformativeText:@"Reset all gamepad bindings to their default values?"];
    [alert setAlertStyle:NSAlertStyleWarning];
    [alert addButtonWithTitle:@"Reset"];
    [alert addButtonWithTitle:@"Cancel"];
    
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            [[InputManager sharedManager] resetGamepadBindingsToDefaults];
            [self loadCurrentBindings];
        }
    }];
}

#pragma mark - NSWindowDelegate

- (void)windowWillClose:(NSNotification *)notification {
    // Reload bindings when reopening (discard unsaved changes)
}

@end
