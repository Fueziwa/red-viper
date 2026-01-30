//
//  EmulatorBridge.h
//  Red Viper - Virtual Boy Emulator for macOS
//
//  Objective-C bridge for the C emulator core
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface EmulatorBridge : NSObject

/// Shared singleton instance
+ (instancetype)sharedBridge;

/// Initialize the emulator core (video, sound, CPU)
- (void)initialize;

/// Shutdown the emulator core and release resources
- (void)shutdown;

/// Load a ROM file at the given path
/// @param path Path to the ROM file (.vb)
/// @param error Error output if loading fails
/// @return YES if ROM loaded successfully
- (BOOL)loadROMAtPath:(NSString *)path error:(NSError * _Nullable * _Nullable)error;

/// Check if a ROM is currently loaded
- (BOOL)isROMLoaded;

/// Run one frame of emulation
- (void)runFrame;

/// Reset the emulator (keeps ROM loaded)
- (void)reset;

/// Callback invoked when a new frame is ready for display
/// Set this to update the display texture when the C core completes a frame.
@property (copy, nonatomic, nullable) void (^frameCallback)(void);

@end

NS_ASSUME_NONNULL_END
