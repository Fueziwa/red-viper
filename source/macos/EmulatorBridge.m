//
//  EmulatorBridge.m
//  Red Viper - Virtual Boy Emulator for macOS
//
//  Objective-C bridge for the C emulator core
//

#import "EmulatorBridge.h"

// C core headers
#include "v810_cpu.h"
#include "vb_set.h"
#include "vb_dsp.h"
#include "vb_sound.h"
#include "replay.h"

@implementation EmulatorBridge {
    BOOL _initialized;
    BOOL _romLoaded;
}

+ (instancetype)sharedBridge {
    static EmulatorBridge *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[EmulatorBridge alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _initialized = NO;
        _romLoaded = NO;
    }
    return self;
}

- (void)initialize {
    if (_initialized) return;
    
    NSLog(@"EmulatorBridge: Initializing emulator core...");
    
    // Set defaults before any other initialization
    setDefaults();
    
    // Initialize video subsystem (stubs for now)
    video_init();
    
    // Initialize sound subsystem (stubs for now)
    sound_init();
    
    // Initialize the V810 CPU
    v810_init();
    
    // Initialize replay system (needed by core)
    replay_init();
    
    _initialized = YES;
    NSLog(@"EmulatorBridge: Core initialized successfully");
}

- (void)shutdown {
    if (!_initialized) return;
    
    NSLog(@"EmulatorBridge: Shutting down...");
    
    sound_close();
    video_quit();
    v810_exit();
    
    _initialized = NO;
    _romLoaded = NO;
    
    NSLog(@"EmulatorBridge: Shutdown complete");
}

- (BOOL)loadROMAtPath:(NSString *)path error:(NSError * _Nullable *)error {
    // ROM loading will be implemented in Plan 03
    NSLog(@"EmulatorBridge: loadROMAtPath: not yet implemented (path=%@)", path);
    if (error) {
        *error = [NSError errorWithDomain:@"RedViperErrorDomain" 
                                     code:-1 
                                 userInfo:@{NSLocalizedDescriptionKey: @"ROM loading not implemented yet"}];
    }
    return NO;
}

- (BOOL)isROMLoaded {
    return _romLoaded;
}

- (void)runFrame {
    if (!_romLoaded) return;
    // Frame execution will be implemented when ROM loading works
}

- (void)reset {
    if (!_initialized) return;
    NSLog(@"EmulatorBridge: Resetting CPU...");
    v810_reset();
}

@end
