//
//  KeyCaptureField.h
//  Red Viper - Virtual Boy Emulator for macOS
//
//  Custom NSTextField subclass for press-to-assign key binding capture
//

#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>

NS_ASSUME_NONNULL_BEGIN

@class KeyCaptureField;

@protocol KeyCaptureFieldDelegate <NSObject>
- (void)keyCaptureField:(KeyCaptureField *)field didCaptureKeyCode:(unsigned short)keyCode;
@end

@interface KeyCaptureField : NSTextField

@property (nonatomic, weak, nullable) id<KeyCaptureFieldDelegate> captureDelegate;
@property (nonatomic, assign) unsigned short capturedKeyCode;
@property (nonatomic, assign, getter=isCapturing) BOOL capturing;

/// Start capturing next keypress
- (void)startCapturing;

/// Stop capturing and revert display
- (void)cancelCapturing;

/// Get display name for a key code
+ (NSString *)displayNameForKeyCode:(unsigned short)keyCode;

@end

NS_ASSUME_NONNULL_END
