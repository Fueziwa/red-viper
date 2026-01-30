//
//  ControlsConfigController.m
//  Red Viper - Virtual Boy Emulator for macOS
//
//  Modal dialog controller for configuring keyboard controls
//

#import "ControlsConfigController.h"
#import "KeyCaptureField.h"
#import "InputManager.h"

/// Dialog dimensions
static const CGFloat kDialogWidth = 500.0;
static const CGFloat kDialogHeight = 480.0;
static const CGFloat kMargin = 20.0;
static const CGFloat kRowHeight = 28.0;
static const CGFloat kLabelWidth = 140.0;
static const CGFloat kFieldWidth = 120.0;

@interface ControlsConfigController () <KeyCaptureFieldDelegate>
@end

@implementation ControlsConfigController {
    NSWindow *_dialogWindow;
    NSWindow *_parentWindow;
    
    /// Working copy of bindings (VBButton -> keyCode)
    NSMutableDictionary<NSNumber *, NSNumber *> *_pendingBindings;
    
    /// KeyCaptureFields indexed by VBButton
    NSMutableArray<KeyCaptureField *> *_captureFields;
}

#pragma mark - Public API

- (void)showModalForWindow:(NSWindow *)parentWindow {
    _parentWindow = parentWindow;
    
    // Copy current bindings to working copy
    _pendingBindings = [[NSMutableDictionary alloc] init];
    for (NSInteger i = 0; i < VBButtonCount; i++) {
        unsigned short keyCode = [[InputManager sharedManager] keyCodeForButton:(VBButton)i];
        _pendingBindings[@(i)] = @(keyCode);
    }
    
    // Build the dialog window
    [self buildDialogWindow];
    
    // Show as sheet
    [_parentWindow beginSheet:_dialogWindow completionHandler:^(NSModalResponse returnCode) {
        // Cleanup handled in button actions
    }];
}

#pragma mark - Dialog Construction

- (void)buildDialogWindow {
    NSRect frame = NSMakeRect(0, 0, kDialogWidth, kDialogHeight);
    
    _dialogWindow = [[NSWindow alloc] initWithContentRect:frame
                                                styleMask:NSWindowStyleMaskTitled
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    [_dialogWindow setTitle:@"Configure Controls"];
    
    NSView *contentView = [_dialogWindow contentView];
    _captureFields = [[NSMutableArray alloc] init];
    
    // Title label
    NSTextField *titleLabel = [self createLabelWithText:@"Configure Keyboard Controls"];
    [titleLabel setFont:[NSFont boldSystemFontOfSize:14]];
    [titleLabel setAlignment:NSTextAlignmentCenter];
    [titleLabel setFrame:NSMakeRect(kMargin, kDialogHeight - 50, kDialogWidth - kMargin * 2, 24)];
    [contentView addSubview:titleLabel];
    
    // Create two columns: Left D-Pad on left, Right D-Pad on right
    // Then action buttons below
    
    CGFloat leftColumnX = kMargin;
    CGFloat rightColumnX = kDialogWidth / 2 + 10;
    CGFloat startY = kDialogHeight - 90;
    
    // Left column: Left D-Pad
    [self addSectionLabel:@"Left D-Pad" atX:leftColumnX y:startY toView:contentView];
    CGFloat y = startY - kRowHeight;
    y = [self addButtonRow:VBButtonLPadUp    atX:leftColumnX y:y toView:contentView];
    y = [self addButtonRow:VBButtonLPadDown  atX:leftColumnX y:y toView:contentView];
    y = [self addButtonRow:VBButtonLPadLeft  atX:leftColumnX y:y toView:contentView];
    y = [self addButtonRow:VBButtonLPadRight atX:leftColumnX y:y toView:contentView];
    
    // Left column: Action buttons
    y -= 10;
    [self addSectionLabel:@"Buttons" atX:leftColumnX y:y toView:contentView];
    y -= kRowHeight;
    y = [self addButtonRow:VBButtonA atX:leftColumnX y:y toView:contentView];
    y = [self addButtonRow:VBButtonB atX:leftColumnX y:y toView:contentView];
    
    // Left column: Start/Select
    y -= 10;
    [self addSectionLabel:@"System" atX:leftColumnX y:y toView:contentView];
    y -= kRowHeight;
    y = [self addButtonRow:VBButtonStart  atX:leftColumnX y:y toView:contentView];
    y = [self addButtonRow:VBButtonSelect atX:leftColumnX y:y toView:contentView];
    
    // Right column: Right D-Pad
    y = startY;
    [self addSectionLabel:@"Right D-Pad" atX:rightColumnX y:y toView:contentView];
    y -= kRowHeight;
    y = [self addButtonRow:VBButtonRPadUp    atX:rightColumnX y:y toView:contentView];
    y = [self addButtonRow:VBButtonRPadDown  atX:rightColumnX y:y toView:contentView];
    y = [self addButtonRow:VBButtonRPadLeft  atX:rightColumnX y:y toView:contentView];
    y = [self addButtonRow:VBButtonRPadRight atX:rightColumnX y:y toView:contentView];
    
    // Right column: Triggers
    y -= 10;
    [self addSectionLabel:@"Triggers" atX:rightColumnX y:y toView:contentView];
    y -= kRowHeight;
    y = [self addButtonRow:VBButtonL atX:rightColumnX y:y toView:contentView];
    y = [self addButtonRow:VBButtonR atX:rightColumnX y:y toView:contentView];
    
    // Bottom buttons
    CGFloat buttonY = kMargin;
    CGFloat buttonWidth = 130;
    CGFloat buttonHeight = 32;
    
    // Reset to Defaults button (left)
    NSButton *resetButton = [[NSButton alloc] initWithFrame:NSMakeRect(kMargin, buttonY, buttonWidth, buttonHeight)];
    [resetButton setTitle:@"Reset to Defaults"];
    [resetButton setBezelStyle:NSBezelStyleRounded];
    [resetButton setTarget:self];
    [resetButton setAction:@selector(resetToDefaultsPressed:)];
    [contentView addSubview:resetButton];
    
    // OK button (right)
    NSButton *okButton = [[NSButton alloc] initWithFrame:NSMakeRect(kDialogWidth - kMargin - buttonWidth, buttonY, buttonWidth, buttonHeight)];
    [okButton setTitle:@"OK"];
    [okButton setBezelStyle:NSBezelStyleRounded];
    [okButton setKeyEquivalent:@"\r"];  // Return key
    [okButton setTarget:self];
    [okButton setAction:@selector(okPressed:)];
    [contentView addSubview:okButton];
    
    // Cancel button (to left of OK)
    NSButton *cancelButton = [[NSButton alloc] initWithFrame:NSMakeRect(kDialogWidth - kMargin - buttonWidth * 2 - 10, buttonY, buttonWidth, buttonHeight)];
    [cancelButton setTitle:@"Cancel"];
    [cancelButton setBezelStyle:NSBezelStyleRounded];
    [cancelButton setKeyEquivalent:@"\033"];  // Escape key
    [cancelButton setTarget:self];
    [cancelButton setAction:@selector(cancelPressed:)];
    [contentView addSubview:cancelButton];
}

- (void)addSectionLabel:(NSString *)text atX:(CGFloat)x y:(CGFloat)y toView:(NSView *)view {
    NSTextField *label = [self createLabelWithText:text];
    [label setFont:[NSFont boldSystemFontOfSize:12]];
    [label setFrame:NSMakeRect(x, y, kLabelWidth + kFieldWidth, 20)];
    [view addSubview:label];
}

- (CGFloat)addButtonRow:(VBButton)button atX:(CGFloat)x y:(CGFloat)y toView:(NSView *)view {
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
    [field setEditable:NO];  // Not directly editable - click to capture
    [field setCaptureDelegate:self];
    
    // Set current key code
    unsigned short keyCode = [_pendingBindings[@(button)] unsignedShortValue];
    [field setCapturedKeyCode:keyCode];
    [field setStringValue:[KeyCaptureField displayNameForKeyCode:keyCode]];
    
    // Store at the correct index
    while (_captureFields.count <= button) {
        [_captureFields addObject:[[KeyCaptureField alloc] init]];  // Placeholder
    }
    _captureFields[button] = field;
    
    [view addSubview:field];
    
    return y - kRowHeight;
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

#pragma mark - KeyCaptureFieldDelegate

- (void)keyCaptureField:(KeyCaptureField *)field didCaptureKeyCode:(unsigned short)keyCode {
    // Find which button this field represents
    NSUInteger index = [_captureFields indexOfObject:field];
    if (index == NSNotFound || index >= VBButtonCount) {
        return;
    }
    
    VBButton button = (VBButton)index;
    
    // Update pending bindings
    _pendingBindings[@(button)] = @(keyCode);
    
    // Update field display
    [field setStringValue:[KeyCaptureField displayNameForKeyCode:keyCode]];
}

#pragma mark - Button Actions

- (void)okPressed:(id)sender {
    // Apply all pending bindings to InputManager
    for (NSNumber *buttonNum in _pendingBindings) {
        VBButton button = (VBButton)[buttonNum integerValue];
        unsigned short keyCode = [_pendingBindings[buttonNum] unsignedShortValue];
        [[InputManager sharedManager] setKeyCode:keyCode forButton:button];
    }
    
    // Save to UserDefaults
    [[InputManager sharedManager] saveBindings];
    
    // Close sheet
    [_parentWindow endSheet:_dialogWindow returnCode:NSModalResponseOK];
    [_dialogWindow close];
}

- (void)cancelPressed:(id)sender {
    // Discard pending bindings, close sheet
    [_parentWindow endSheet:_dialogWindow returnCode:NSModalResponseCancel];
    [_dialogWindow close];
}

- (void)resetToDefaultsPressed:(id)sender {
    // Show confirmation alert
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"Reset Key Bindings"];
    [alert setInformativeText:@"Reset all key bindings to their default values?"];
    [alert setAlertStyle:NSAlertStyleWarning];
    [alert addButtonWithTitle:@"Reset"];
    [alert addButtonWithTitle:@"Cancel"];
    
    [alert beginSheetModalForWindow:_dialogWindow completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            [self performResetToDefaults];
        }
    }];
}

- (void)performResetToDefaults {
    // Reset InputManager to defaults
    [[InputManager sharedManager] resetToDefaults];
    
    // Copy fresh defaults to pending bindings
    for (NSInteger i = 0; i < VBButtonCount; i++) {
        unsigned short keyCode = [[InputManager sharedManager] keyCodeForButton:(VBButton)i];
        _pendingBindings[@(i)] = @(keyCode);
        
        // Update field display
        if (i < (NSInteger)_captureFields.count) {
            KeyCaptureField *field = _captureFields[i];
            [field setCapturedKeyCode:keyCode];
            [field setStringValue:[KeyCaptureField displayNameForKeyCode:keyCode]];
        }
    }
}

@end
