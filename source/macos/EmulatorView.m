//
//  EmulatorView.m
//  Red Viper - Virtual Boy Emulator for macOS
//
//  NSOpenGLView subclass for rendering Virtual Boy framebuffer
//

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

#import "EmulatorView.h"
#import <OpenGL/gl.h>
#import <CoreVideo/CoreVideo.h>
#import <mach/mach_time.h>
#import "EmulatorBridge.h"
#import "InputManager.h"

// C core headers for framebuffer access
#include "v810_mem.h"
#include "vb_dsp.h"

// Sound functions from vb_sound_macos.c
extern void sound_pause(void);
extern void sound_resume(void);

/// Virtual Boy display resolution
const NSInteger kVBDisplayWidth = 384;
const NSInteger kVBDisplayHeight = 224;

/// Calculate brightness values from VIP registers (like linux-test)
/// The VB uses red LEDs with brightness controlled by BRTA, BRTB, BRTC registers
static void getBrightnessLevels(uint8_t *levels) {
    if (!vb_state) {
        levels[0] = 0;
        levels[1] = 64;
        levels[2] = 128;
        levels[3] = 255;
        return;
    }
    
    // Use VIP brightness registers like linux-test does
    // shade[0] = 0 (black)
    // shade[1] = BRTA
    // shade[2] = BRTB  
    // shade[3] = BRTA + BRTB + BRTC
    uint32_t brta = vb_state->tVIPREG.BRTA;
    uint32_t brtb = vb_state->tVIPREG.BRTB;
    uint32_t brtc = vb_state->tVIPREG.BRTC;
    
    uint32_t shade0 = 0;
    uint32_t shade1 = brta * 2;
    uint32_t shade2 = brtb * 2;
    uint32_t shade3 = (brta + brtb + brtc) * 2;
    
    // Clamp to 255
    levels[0] = shade0 > 255 ? 255 : (uint8_t)shade0;
    levels[1] = shade1 > 255 ? 255 : (uint8_t)shade1;
    levels[2] = shade2 > 255 ? 255 : (uint8_t)shade2;
    levels[3] = shade3 > 255 ? 255 : (uint8_t)shade3;
}

// Forward declaration for private methods
@interface EmulatorView ()
- (void)renderFrame;
- (void)startDisplayLink;
- (void)stopDisplayLink;
@end

#pragma mark - CVDisplayLink Callback

// CVDisplayLink callback runs on a high-priority background thread
// Must dispatch to main thread for UI/OpenGL work
static CVReturn displayLinkCallback(CVDisplayLinkRef displayLink,
                                    const CVTimeStamp *now,
                                    const CVTimeStamp *outputTime,
                                    CVOptionFlags flagsIn,
                                    CVOptionFlags *flagsOut,
                                    void *displayLinkContext) {
    @autoreleasepool {
        EmulatorView *view = (__bridge EmulatorView *)displayLinkContext;
        [view renderFrame];
    }
    return kCVReturnSuccess;
}

@implementation EmulatorView {
    GLuint _displayTexture;
    uint8_t *_pixelBuffer;  // RGBA pixel buffer (384 * 224 * 4 bytes)
    NSInteger _currentScale;
    CVDisplayLinkRef _displayLink;
    BOOL _running;
    
    // Frame pacing timer (50.27 Hz, decoupled from display refresh)
    dispatch_source_t _frameTimer;
    dispatch_queue_t _frameTimerQueue;
}

#pragma mark - Initialization

- (instancetype)initWithFrame:(NSRect)frameRect {
    // Create pixel format for OpenGL 2.1 legacy profile
    NSOpenGLPixelFormatAttribute attrs[] = {
        NSOpenGLPFADoubleBuffer,
        NSOpenGLPFAOpenGLProfile, NSOpenGLProfileVersionLegacy,
        NSOpenGLPFAColorSize, 24,
        NSOpenGLPFADepthSize, 0,  // No depth buffer needed for 2D
        0
    };
    
    NSOpenGLPixelFormat *pixelFormat = [[NSOpenGLPixelFormat alloc] initWithAttributes:attrs];
    if (!pixelFormat) {
        NSLog(@"EmulatorView: Failed to create pixel format");
        return nil;
    }
    
    self = [super initWithFrame:frameRect pixelFormat:pixelFormat];
    if (self) {
        _currentScale = 2;  // Default to 2x scale (768x448)
        _displayTexture = 0;
        _displayLink = NULL;
        _running = NO;
        
        // Allocate RGBA pixel buffer
        _pixelBuffer = calloc(kVBDisplayWidth * kVBDisplayHeight * 4, sizeof(uint8_t));
        if (!_pixelBuffer) {
            NSLog(@"EmulatorView: Failed to allocate pixel buffer");
            return nil;
        }
        
        // Register for window focus loss to clear stuck keys
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(windowDidResignKey:)
                                                     name:NSWindowDidResignKeyNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    // Remove notification observer
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    // Stop the display link if running
    [self stopEmulation];
    
    if (_pixelBuffer) {
        free(_pixelBuffer);
        _pixelBuffer = NULL;
    }
    
    if (_displayTexture) {
        [[self openGLContext] makeCurrentContext];
        glDeleteTextures(1, &_displayTexture);
        _displayTexture = 0;
    }
}

#pragma mark - OpenGL Setup

- (void)prepareOpenGL {
    [super prepareOpenGL];
    
    [[self openGLContext] makeCurrentContext];
    
    // Enable VSync
    GLint swapInterval = 1;
    [[self openGLContext] setValues:&swapInterval forParameter:NSOpenGLContextParameterSwapInterval];
    
    // Set up OpenGL state
    glDisable(GL_DEPTH_TEST);
    glDisable(GL_LIGHTING);
    glEnable(GL_TEXTURE_2D);
    
    // Create the display texture
    glGenTextures(1, &_displayTexture);
    glBindTexture(GL_TEXTURE_2D, _displayTexture);
    
    // Use nearest-neighbor filtering for crisp pixels (no bilinear interpolation)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    
    // Initialize texture with empty data (384x224 RGBA)
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA,
                 (GLsizei)kVBDisplayWidth, (GLsizei)kVBDisplayHeight,
                 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
    
    // Set clear color to black
    glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
    
    NSLog(@"EmulatorView: OpenGL initialized, texture ID: %u", _displayTexture);
}

#pragma mark - Framebuffer Conversion

- (void)convertFramebuffer {
    if (!vb_state || !_pixelBuffer) {
        return;
    }
    
    // Get the currently displayed framebuffer (0 or 1)
    int displayedFB = vb_state->tVIPREG.tDisplayedFB;
    
    // Calculate framebuffer address for left eye (eye=0)
    // Left eye FB0 at offset 0x00000, FB1 at offset 0x08000
    uint16_t *fb = (uint16_t *)(vb_state->V810_DISPLAY_RAM.off + 0x8000 * displayedFB);
    
    // Get brightness levels from VIP registers
    uint8_t brightnessLevels[4];
    getBrightnessLevels(brightnessLevels);
    
    // Convert 2-bit packed pixels to RGBA
    // Virtual Boy framebuffer is column-major:
    // - Each column x has 32 uint16_t words (256 pixels, only 224 visible)
    // - Each uint16_t contains 8 pixels (2 bits each)
    // - Pixel (x, y): word = fb[x * 32 + y / 8], shift = (y % 8) * 2, value = (word >> shift) & 0x03
    
    for (int x = 0; x < kVBDisplayWidth; x++) {
        for (int y = 0; y < kVBDisplayHeight; y += 8) {
            // Read a word containing 8 pixels (like linux-test)
            uint16_t vb_word = fb[x * 32 + (y / 8)];
            
            for (int i = 0; i < 8 && (y + i) < kVBDisplayHeight; i++) {
                int shade = vb_word & 0x03;
                uint8_t brightness = brightnessLevels[shade];
                
                // Write RGBA pixel to buffer (red channel only, like VB hardware)
                int pixelOffset = ((y + i) * kVBDisplayWidth + x) * 4;
                _pixelBuffer[pixelOffset + 0] = brightness;  // R
                _pixelBuffer[pixelOffset + 1] = 0;           // G
                _pixelBuffer[pixelOffset + 2] = 0;           // B
                _pixelBuffer[pixelOffset + 3] = 255;         // A
                
                vb_word >>= 2;
            }
        }
    }
}

#pragma mark - Public Methods

- (void)updateTexture {
    [[self openGLContext] makeCurrentContext];
    
    // Convert VB framebuffer to RGBA
    [self convertFramebuffer];
    
    // Upload to GPU
    glBindTexture(GL_TEXTURE_2D, _displayTexture);
    glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0,
                    (GLsizei)kVBDisplayWidth, (GLsizei)kVBDisplayHeight,
                    GL_RGBA, GL_UNSIGNED_BYTE, _pixelBuffer);
    
    // Request redraw
    [self setNeedsDisplay:YES];
}

- (void)setScale:(NSInteger)scale {
    // Clamp scale to valid range
    if (scale < 1) scale = 1;
    if (scale > 4) scale = 4;
    
    _currentScale = scale;
    
    // Resize the view
    NSSize newSize = NSMakeSize(kVBDisplayWidth * scale, kVBDisplayHeight * scale);
    [self setFrameSize:newSize];
    
    NSLog(@"EmulatorView: Scale set to %ldx (%ldx%ld)",
          (long)scale, (long)newSize.width, (long)newSize.height);
}

- (NSInteger)currentScale {
    return _currentScale;
}

#pragma mark - CVDisplayLink Render Loop

- (void)startEmulation {
    [self startDisplayLink];
}

- (void)stopEmulation {
    [self stopDisplayLink];
}

- (void)startDisplayLink {
    if (_running) {
        return;  // Already running
    }
    
    // Create display link for vsync'd rendering (display refresh, NOT emulation)
    CVReturn result = CVDisplayLinkCreateWithActiveCGDisplays(&_displayLink);
    if (result != kCVReturnSuccess) {
        NSLog(@"EmulatorView: Failed to create CVDisplayLink (error %d)", result);
        return;
    }
    
    // Set the output callback - CVDisplayLink only triggers redraws, not emulation
    CVDisplayLinkSetOutputCallback(_displayLink, displayLinkCallback, (__bridge void *)self);
    
    // Set up the frame callback on EmulatorBridge to update texture when frame ready
    __weak EmulatorView *weakSelf = self;
    [[EmulatorBridge sharedBridge] setFrameCallback:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            EmulatorView *strongSelf = weakSelf;
            if (strongSelf) {
                [strongSelf updateTexture];
                [strongSelf setNeedsDisplay:YES];
            }
        });
    }];
    
    // Create dispatch_source timer for accurate 50.27 Hz frame pacing
    // Virtual Boy runs at 50.27 Hz (20,000,000 cycles at ~1 MHz clock)
    // Timer interval: 1,000,000,000 ns / 50.27 Hz ≈ 19,892,577 ns
    _frameTimerQueue = dispatch_queue_create("com.redviper.frametimer", DISPATCH_QUEUE_SERIAL);
    _frameTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _frameTimerQueue);
    
    // Set timer to fire every 19.89ms (50.27 Hz) with 1ms leeway
    uint64_t intervalNs = (uint64_t)(1000000000.0 / 50.27);  // ~19,892,577 ns
    dispatch_source_set_timer(_frameTimer, DISPATCH_TIME_NOW, intervalNs, 1000000);  // 1ms leeway
    
    dispatch_source_set_event_handler(_frameTimer, ^{
        EmulatorView *strongSelf = weakSelf;
        if (strongSelf && strongSelf->_running) {
            if ([[EmulatorBridge sharedBridge] isROMLoaded]) {
                [[EmulatorBridge sharedBridge] runFrame];
                
                // Debug: Frame rate logging (fires every second)
#ifdef DEBUG
                static uint64_t frameCount = 0;
                static uint64_t lastLogTime = 0;
                
                frameCount++;
                
                // Get current time in nanoseconds
                mach_timebase_info_data_t timebase;
                mach_timebase_info(&timebase);
                uint64_t now = mach_absolute_time();
                uint64_t nowNs = now * timebase.numer / timebase.denom;
                
                // Log every second
                if (nowNs - lastLogTime >= 1000000000ULL) {
                    NSLog(@"Frame rate: %llu fps (target: 50.27)", frameCount);
                    frameCount = 0;
                    lastLogTime = nowNs;
                }
#endif
            }
        }
    });
    
    // Start the display link (for vsync'd rendering)
    CVDisplayLinkStart(_displayLink);
    
    // Start the frame timer (for emulation at 50.27 Hz)
    dispatch_resume(_frameTimer);
    
    _running = YES;
    
    // Resume audio when emulation starts
    sound_resume();
    
    NSLog(@"EmulatorView: Emulation started (50.27 Hz frame timer + CVDisplayLink for vsync)");
}

- (void)stopDisplayLink {
    if (!_running) {
        return;  // Already stopped
    }
    
    // Pause audio when emulation stops
    sound_pause();
    
    // Stop and release the frame timer
    if (_frameTimer) {
        dispatch_source_cancel(_frameTimer);
        _frameTimer = nil;
    }
    _frameTimerQueue = nil;
    
    // Stop and release display link
    if (_displayLink) {
        CVDisplayLinkStop(_displayLink);
        CVDisplayLinkRelease(_displayLink);
        _displayLink = NULL;
    }
    
    // Clear frame callback
    [[EmulatorBridge sharedBridge] setFrameCallback:nil];
    
    _running = NO;
    
    NSLog(@"EmulatorView: Emulation stopped");
}

- (void)renderFrame {
    if (!_running) {
        return;
    }
    
    // CVDisplayLink callback now ONLY triggers display refresh (vsync)
    // Emulation runs on the separate dispatch_source timer at 50.27 Hz
    // This may show some frames twice or skip some if rates don't align,
    // but emulation runs at correct Virtual Boy speed
    dispatch_async(dispatch_get_main_queue(), ^{
        [self setNeedsDisplay:YES];
    });
}

#pragma mark - Drawing

- (void)reshape {
    [super reshape];
    
    [[self openGLContext] makeCurrentContext];
    
    NSRect bounds = [self bounds];
    glViewport(0, 0, (GLsizei)bounds.size.width, (GLsizei)bounds.size.height);
    
    // Set up orthographic projection
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    glOrtho(-1.0, 1.0, -1.0, 1.0, -1.0, 1.0);
    
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();
}

- (void)drawRect:(NSRect)dirtyRect {
    [[self openGLContext] makeCurrentContext];
    
    // Clear to black
    glClear(GL_COLOR_BUFFER_BIT);
    
    // Draw textured quad
    glEnable(GL_TEXTURE_2D);
    glBindTexture(GL_TEXTURE_2D, _displayTexture);
    
    glBegin(GL_QUADS);
        // Bottom-left
        glTexCoord2f(0.0f, 1.0f);
        glVertex2f(-1.0f, -1.0f);
        
        // Bottom-right
        glTexCoord2f(1.0f, 1.0f);
        glVertex2f(1.0f, -1.0f);
        
        // Top-right
        glTexCoord2f(1.0f, 0.0f);
        glVertex2f(1.0f, 1.0f);
        
        // Top-left
        glTexCoord2f(0.0f, 0.0f);
        glVertex2f(-1.0f, 1.0f);
    glEnd();
    
    // Swap buffers
    [[self openGLContext] flushBuffer];
}

#pragma mark - View Properties

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (BOOL)isOpaque {
    return YES;
}

#pragma mark - Keyboard Events

- (void)keyDown:(NSEvent *)event {
    [[InputManager sharedManager] keyDown:event];
}

- (void)keyUp:(NSEvent *)event {
    [[InputManager sharedManager] keyUp:event];
}

- (void)flagsChanged:(NSEvent *)event {
    [[InputManager sharedManager] flagsChanged:event];
}

#pragma mark - Window Focus

- (void)windowDidResignKey:(NSNotification *)notification {
    [[InputManager sharedManager] clearAllKeys];
}

@end

#pragma clang diagnostic pop
