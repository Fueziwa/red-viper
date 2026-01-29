//
//  ROMLoader.m
//  Red Viper - Virtual Boy Emulator for macOS
//
//  Handles ROM file loading and ZIP archive extraction
//

#import "ROMLoader.h"
#import <archive.h>
#import <archive_entry.h>

NSString * const ROMLoaderErrorDomain = @"com.redviper.romloader";

// ROM size limits
static const NSUInteger kMinROMSize = 16;              // 16 bytes minimum
static const NSUInteger kMaxROMSize = 16 * 1024 * 1024; // 16 MB maximum

@implementation ROMLoader {
    NSString *_tempDirectory;
    NSString *_extractedROMPath;
}

+ (instancetype)sharedLoader {
    static ROMLoader *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[ROMLoader alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _tempDirectory = nil;
        _extractedROMPath = nil;
    }
    return self;
}

- (NSString *)tempDirectory {
    return _tempDirectory;
}

#pragma mark - Public Methods

- (nullable NSString *)loadROMAtPath:(NSString *)path error:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    
    // Check if file exists
    if (![fm fileExistsAtPath:path]) {
        if (error) {
            *error = [NSError errorWithDomain:ROMLoaderErrorDomain
                                         code:ROMLoaderErrorFileNotFound
                                     userInfo:@{NSLocalizedDescriptionKey: @"ROM file not found"}];
        }
        return nil;
    }
    
    NSString *romPath = path;
    
    // Handle ZIP files
    if ([self isZIPFile:path]) {
        NSLog(@"ROMLoader: Detected ZIP archive, extracting...");
        romPath = [self extractROMFromZIP:path error:error];
        if (!romPath) {
            return nil;
        }
    }
    
    // Validate ROM size
    if (![self validateROMSize:romPath error:error]) {
        // Clean up if we extracted a file
        if (_extractedROMPath) {
            [self cleanup];
        }
        return nil;
    }
    
    NSLog(@"ROMLoader: ROM ready at %@", romPath);
    return romPath;
}

- (BOOL)isZIPFile:(NSString *)path {
    return [[path.pathExtension lowercaseString] isEqualToString:@"zip"];
}

- (BOOL)validateROMSize:(NSString *)path error:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDictionary *attrs = [fm attributesOfItemAtPath:path error:nil];
    
    if (!attrs) {
        if (error) {
            *error = [NSError errorWithDomain:ROMLoaderErrorDomain
                                         code:ROMLoaderErrorIOError
                                     userInfo:@{NSLocalizedDescriptionKey: @"Cannot read ROM file attributes"}];
        }
        return NO;
    }
    
    unsigned long long fileSize = [attrs fileSize];
    
    // Check minimum size
    if (fileSize < kMinROMSize) {
        if (error) {
            *error = [NSError errorWithDomain:ROMLoaderErrorDomain
                                         code:ROMLoaderErrorInvalidROMSize
                                     userInfo:@{NSLocalizedDescriptionKey: 
                                         [NSString stringWithFormat:@"ROM too small: %llu bytes (minimum %lu)", 
                                          fileSize, (unsigned long)kMinROMSize]}];
        }
        return NO;
    }
    
    // Check maximum size
    if (fileSize > kMaxROMSize) {
        if (error) {
            *error = [NSError errorWithDomain:ROMLoaderErrorDomain
                                         code:ROMLoaderErrorInvalidROMSize
                                     userInfo:@{NSLocalizedDescriptionKey: 
                                         [NSString stringWithFormat:@"ROM too large: %llu bytes (maximum %lu)", 
                                          fileSize, (unsigned long)kMaxROMSize]}];
        }
        return NO;
    }
    
    // Check if power of 2 (Virtual Boy ROMs should be power-of-2 sized)
    if (![self isPowerOfTwo:fileSize]) {
        // Warn but don't fail - some homebrew ROMs may not be power of 2
        NSLog(@"ROMLoader: Warning - ROM size %llu is not a power of 2", fileSize);
    }
    
    NSLog(@"ROMLoader: ROM size valid: %llu bytes", fileSize);
    return YES;
}

- (void)cleanup {
    if (_tempDirectory) {
        NSLog(@"ROMLoader: Cleaning up temp directory: %@", _tempDirectory);
        [[NSFileManager defaultManager] removeItemAtPath:_tempDirectory error:nil];
        _tempDirectory = nil;
        _extractedROMPath = nil;
    }
}

#pragma mark - Private Methods

- (BOOL)isPowerOfTwo:(unsigned long long)n {
    return n > 0 && (n & (n - 1)) == 0;
}

- (nullable NSString *)extractROMFromZIP:(NSString *)zipPath error:(NSError **)error {
    // Create temp directory
    NSString *tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"RedViper-%@", [[NSUUID UUID] UUIDString]]];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *createError = nil;
    if (![fm createDirectoryAtPath:tempDir withIntermediateDirectories:YES attributes:nil error:&createError]) {
        if (error) {
            *error = [NSError errorWithDomain:ROMLoaderErrorDomain
                                         code:ROMLoaderErrorIOError
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to create temp directory",
                                                NSUnderlyingErrorKey: createError}];
        }
        return nil;
    }
    
    _tempDirectory = tempDir;
    
    // Open the archive with libarchive
    struct archive *a = archive_read_new();
    archive_read_support_format_zip(a);
    archive_read_support_filter_all(a);
    
    int r = archive_read_open_filename(a, [zipPath UTF8String], 10240);
    if (r != ARCHIVE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:ROMLoaderErrorDomain
                                         code:ROMLoaderErrorZIPExtractionFailed
                                     userInfo:@{NSLocalizedDescriptionKey: 
                                         [NSString stringWithFormat:@"Failed to open ZIP: %s", 
                                          archive_error_string(a)]}];
        }
        archive_read_free(a);
        [self cleanup];
        return nil;
    }
    
    // Find and extract the first .vb file
    struct archive_entry *entry;
    NSString *extractedPath = nil;
    
    while (archive_read_next_header(a, &entry) == ARCHIVE_OK) {
        const char *pathname = archive_entry_pathname(entry);
        NSString *filename = [NSString stringWithUTF8String:pathname];
        
        // Check for .vb extension (case insensitive)
        if ([[filename.pathExtension lowercaseString] isEqualToString:@"vb"]) {
            NSLog(@"ROMLoader: Found ROM in archive: %@", filename);
            
            // Extract to temp directory
            NSString *destPath = [tempDir stringByAppendingPathComponent:[filename lastPathComponent]];
            
            if ([self extractEntry:entry fromArchive:a toPath:destPath error:error]) {
                extractedPath = destPath;
                _extractedROMPath = destPath;
                break;
            } else {
                archive_read_free(a);
                [self cleanup];
                return nil;
            }
        } else {
            archive_read_data_skip(a);
        }
    }
    
    archive_read_free(a);
    
    if (!extractedPath) {
        if (error) {
            *error = [NSError errorWithDomain:ROMLoaderErrorDomain
                                         code:ROMLoaderErrorNoROMInArchive
                                     userInfo:@{NSLocalizedDescriptionKey: @"No .vb ROM file found in archive"}];
        }
        [self cleanup];
        return nil;
    }
    
    NSLog(@"ROMLoader: Extracted ROM to: %@", extractedPath);
    return extractedPath;
}

- (BOOL)extractEntry:(struct archive_entry *)entry 
         fromArchive:(struct archive *)a 
              toPath:(NSString *)destPath 
               error:(NSError **)error {
    
    int fd = open([destPath UTF8String], O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) {
        if (error) {
            *error = [NSError errorWithDomain:ROMLoaderErrorDomain
                                         code:ROMLoaderErrorIOError
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to create output file"}];
        }
        return NO;
    }
    
    const void *buff;
    size_t size;
    la_int64_t offset;
    
    while (archive_read_data_block(a, &buff, &size, &offset) == ARCHIVE_OK) {
        if (write(fd, buff, size) != (ssize_t)size) {
            close(fd);
            if (error) {
                *error = [NSError errorWithDomain:ROMLoaderErrorDomain
                                             code:ROMLoaderErrorIOError
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to write ROM data"}];
            }
            return NO;
        }
    }
    
    close(fd);
    return YES;
}

@end
