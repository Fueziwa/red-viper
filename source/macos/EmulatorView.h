//
//  EmulatorView.h
//  Red Viper - Virtual Boy Emulator for macOS
//
//  NSOpenGLView subclass for rendering Virtual Boy framebuffer
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// Virtual Boy display resolution
extern const NSInteger kVBDisplayWidth;   // 384
extern const NSInteger kVBDisplayHeight;  // 224

@interface EmulatorView : NSOpenGLView

/// Current display scale (1-4)
@property (nonatomic, readonly) NSInteger currentScale;

/// Update the texture from the emulator framebuffer
/// Call this when a new frame is ready
- (void)updateTexture;

/// Set the display scale (1-4)
/// Resizes the view to match the scaled resolution
/// @param scale Scale factor (1 = native 384x224, 2 = 768x448, etc.)
- (void)setScale:(NSInteger)scale;

/// Start the emulation render loop (CVDisplayLink)
/// Call this after a ROM is loaded
- (void)startEmulation;

/// Stop the emulation render loop
/// Call this before shutdown or when switching ROMs
- (void)stopEmulation;

@end

NS_ASSUME_NONNULL_END
