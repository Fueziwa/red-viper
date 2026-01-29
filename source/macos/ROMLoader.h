//
//  ROMLoader.h
//  Red Viper - Virtual Boy Emulator for macOS
//
//  Handles ROM file loading and ZIP archive extraction
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Error domain for ROM loading errors
extern NSString * const ROMLoaderErrorDomain;

/// Error codes for ROM loading
typedef NS_ENUM(NSInteger, ROMLoaderError) {
    ROMLoaderErrorFileNotFound = 1,
    ROMLoaderErrorInvalidROMSize,
    ROMLoaderErrorZIPExtractionFailed,
    ROMLoaderErrorNoROMInArchive,
    ROMLoaderErrorIOError,
};

@interface ROMLoader : NSObject

/// Shared singleton instance
+ (instancetype)sharedLoader;

/// Load a ROM file, extracting from ZIP if necessary
/// @param path Path to the ROM file (.vb) or ZIP archive (.zip)
/// @param error Error output if loading fails
/// @return Path to the .vb file to load (original or extracted), or nil on failure
- (nullable NSString *)loadROMAtPath:(NSString *)path error:(NSError **)error;

/// Check if a file is a ZIP archive based on extension
/// @param path Path to check
/// @return YES if the file has a .zip extension
- (BOOL)isZIPFile:(NSString *)path;

/// Validate ROM file size
/// @param path Path to the ROM file
/// @param error Error output if validation fails
/// @return YES if the ROM size is valid (power of 2, 16 bytes to 16MB)
- (BOOL)validateROMSize:(NSString *)path error:(NSError **)error;

/// Clean up any temporary files created during extraction
- (void)cleanup;

/// Get the path to the temporary directory used for extraction
@property (nonatomic, readonly, nullable) NSString *tempDirectory;

@end

NS_ASSUME_NONNULL_END
