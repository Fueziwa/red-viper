//
//  EmulatorBridge.m
//  Red Viper - Virtual Boy Emulator for macOS
//
//  Objective-C bridge for the C emulator core
//

#import "EmulatorBridge.h"
#import "ROMLoader.h"
#import "InputManager.h"

// C core headers
#include "v810_cpu.h"
#include "v810_mem.h"
#include "vb_set.h"
#include "vb_dsp.h"
#include "vb_sound.h"
#include "replay.h"

// Software renderer from video_soft.cpp
extern void video_soft_render(int drawn_fb);
extern void update_texture_cache_soft(void);

// Cache management from video_common.c
extern void clearCache(void);

// External declarations from C core
extern VB_OPT tVBOpt;

@implementation EmulatorBridge {
    BOOL _initialized;
    BOOL _romLoaded;
    NSString *_currentROMPath;
}

@synthesize frameCallback = _frameCallback;

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
        _currentROMPath = nil;
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
    
    // Clean up any extracted ROM files
    [[ROMLoader sharedLoader] cleanup];
    
    sound_close();
    video_quit();
    v810_exit();
    
    _initialized = NO;
    _romLoaded = NO;
    _currentROMPath = nil;
    
    NSLog(@"EmulatorBridge: Shutdown complete");
}

- (BOOL)loadROMAtPath:(NSString *)path error:(NSError * _Nullable *)error {
    if (!_initialized) {
        if (error) {
            *error = [NSError errorWithDomain:@"RedViperErrorDomain"
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Emulator not initialized"}];
        }
        return NO;
    }
    
    NSLog(@"EmulatorBridge: Loading ROM at path: %@", path);
    
    // Use ROMLoader to handle ZIP extraction if needed
    ROMLoader *loader = [ROMLoader sharedLoader];
    NSString *romPath = [loader loadROMAtPath:path error:error];
    
    if (!romPath) {
        NSLog(@"EmulatorBridge: ROMLoader failed to load ROM");
        return NO;
    }
    
    // Generate RAM path (save file) - same directory as ROM with .ram extension
    NSString *ramPath = [[romPath stringByDeletingPathExtension] stringByAppendingPathExtension:@"ram"];
    
    // Set up the C core paths
    const char *romPathC = [romPath UTF8String];
    const char *ramPathC = [ramPath UTF8String];
    
    // Copy paths into tVBOpt structure
    strncpy(tVBOpt.ROM_PATH, romPathC, sizeof(tVBOpt.ROM_PATH) - 1);
    tVBOpt.ROM_PATH[sizeof(tVBOpt.ROM_PATH) - 1] = '\0';
    
    strncpy(tVBOpt.RAM_PATH, ramPathC, sizeof(tVBOpt.RAM_PATH) - 1);
    tVBOpt.RAM_PATH[sizeof(tVBOpt.RAM_PATH) - 1] = '\0';
    
    NSLog(@"EmulatorBridge: ROM_PATH=%s", tVBOpt.ROM_PATH);
    NSLog(@"EmulatorBridge: RAM_PATH=%s", tVBOpt.RAM_PATH);
    
    // Initialize ROM loading
    int result = v810_load_init();
    if (result != 0) {
        NSLog(@"EmulatorBridge: v810_load_init failed with error: %d", result);
        if (error) {
            *error = [NSError errorWithDomain:@"RedViperErrorDomain"
                                         code:result
                                     userInfo:@{NSLocalizedDescriptionKey: 
                                         [NSString stringWithFormat:@"Failed to initialize ROM loading (error %d)", result]}];
        }
        [loader cleanup];
        return NO;
    }
    
    // Load ROM in steps, showing progress
    int progress = 0;
    int lastLoggedProgress = -1;
    
    while (progress < 100) {
        progress = v810_load_step();
        
        if (progress < 0) {
            NSLog(@"EmulatorBridge: v810_load_step failed with error: %d", progress);
            if (error) {
                *error = [NSError errorWithDomain:@"RedViperErrorDomain"
                                             code:progress
                                         userInfo:@{NSLocalizedDescriptionKey: 
                                             [NSString stringWithFormat:@"ROM loading failed (error %d)", progress]}];
            }
            v810_load_cancel();
            [loader cleanup];
            return NO;
        }
        
        // Log progress at 10% intervals
        if (progress / 10 > lastLoggedProgress / 10) {
            NSLog(@"Loading... %d%%", progress);
            lastLoggedProgress = progress;
        }
    }
    
    NSLog(@"Loading... 100%%");
    NSLog(@"ROM loaded successfully!");
    
    // Log ROM info
    NSLog(@"Game ID: %.5s, CRC32: 0x%08lX", tVBOpt.GAME_ID, tVBOpt.CRC32);
    
    // Log CPU state
    NSLog(@"V810 PC at 0x%08X - CPU ready to execute", vb_state->v810_state.PC);
    
    _romLoaded = YES;
    _currentROMPath = romPath;
    
    // Use software rendering mode (like linux-test does)
    // macOS doesn't have 3DS GPU hardware, so we use CPU-only rendering
    tVBOpt.RENDERMODE = RM_CPUONLY;
    
    // Initialize display cache - required for software renderer to work
    clearCache();
    
    return YES;
}

- (BOOL)isROMLoaded {
    return _romLoaded;
}

- (void)runFrame {
    if (!_romLoaded) return;
    
    // Clear cache every frame like linux-test does
    clearCache();
    
    // Check if we should render (same conditions as linux-test/main.c)
    // Must check BEFORE v810_run() modifies state
    BOOL shouldRender = (vb_state->tVIPREG.tFrame == 0 &&
                         !vb_state->tVIPREG.drawing &&
                         (vb_state->tVIPREG.XPCTRL & XPEN));
    
    if (shouldRender) {
        // Update tile cache if needed
        if (tDSPCACHE.CharCacheInvalid) {
            update_texture_cache_soft();
        }
        
        // Render to the non-displayed framebuffer
        video_soft_render(!vb_state->tVIPREG.tDisplayedFB);
        
        // Clear cache flags after rendering
        tDSPCACHE.CharCacheInvalid = false;
        memset(tDSPCACHE.BGCacheInvalid, 0, sizeof(tDSPCACHE.BGCacheInvalid));
        memset(tDSPCACHE.CharacterCache, 0, sizeof(tDSPCACHE.CharacterCache));
    }
    
    // Always update the display (like linux-test sdl_flush)
    // This shows whatever is in the current displayed framebuffer
    if (self.frameCallback) {
        self.frameCallback();
    }
    
    // Write input state to hardware registers before CPU execution
    // Games read input from 0x02000010 (SLB) and 0x02000014 (SHB)
    uint16_t inputs = InputManager_currentControllerState();
    vb_state->tHReg.SLB = inputs & 0xFF;
    vb_state->tHReg.SHB = (inputs >> 8) & 0xFF;
    
    // Run one frame of emulation
    v810_run();
}

- (void)reset {
    if (!_initialized) return;
    NSLog(@"EmulatorBridge: Resetting CPU...");
    v810_reset();
}

@end
