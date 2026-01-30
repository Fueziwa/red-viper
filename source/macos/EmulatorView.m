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
#import "EmulatorBridge.h"

// C core headers for framebuffer access
#include "v810_mem.h"
#include "vb_dsp.h"

/// Virtual Boy display resolution
const NSInteger kVBDisplayWidth = 384;
const NSInteger kVBDisplayHeight = 224;

/// Hardware-accurate Virtual Boy red palette
/// The VB uses red LEDs with 4 brightness levels
static const uint8_t kRedPalette[4][4] = {
    {0,   0, 0, 255},  // Shade 0: Black (off)
    {64,  0, 0, 255},  // Shade 1: Dark red
    {128, 0, 0, 255},  // Shade 2: Medium red
    {255, 0, 0, 255},  // Shade 3: Bright red
};

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
    }
    return self;
}

- (void)dealloc {
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
    
    // Convert 2-bit packed pixels to RGBA
    // Virtual Boy framebuffer is column-major:
    // - Each column x has 32 uint16_t words (256 pixels, only 224 visible)
    // - Each uint16_t contains 8 pixels (2 bits each)
    // - Pixel (x, y): word = fb[x * 32 + y / 8], shift = (y % 8) * 2, value = (word >> shift) & 0x03
    
    for (int x = 0; x < kVBDisplayWidth; x++) {
        for (int y = 0; y < kVBDisplayHeight; y++) {
            int wordIndex = x * 32 + (y >> 3);
            int shift = (y & 7) * 2;
            int shade = (fb[wordIndex] >> shift) & 0x03;
            
            // Write RGBA pixel to buffer
            int pixelOffset = (y * kVBDisplayWidth + x) * 4;
            _pixelBuffer[pixelOffset + 0] = kRedPalette[shade][0];  // R
            _pixelBuffer[pixelOffset + 1] = kRedPalette[shade][1];  // G
            _pixelBuffer[pixelOffset + 2] = kRedPalette[shade][2];  // B
            _pixelBuffer[pixelOffset + 3] = kRedPalette[shade][3];  // A
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
    
    // Create display link
    CVReturn result = CVDisplayLinkCreateWithActiveCGDisplays(&_displayLink);
    if (result != kCVReturnSuccess) {
        NSLog(@"EmulatorView: Failed to create CVDisplayLink (error %d)", result);
        return;
    }
    
    // Set the output callback
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
    
    // Start the display link
    CVDisplayLinkStart(_displayLink);
    _running = YES;
    
    NSLog(@"EmulatorView: Emulation started (CVDisplayLink active)");
}

- (void)stopDisplayLink {
    if (!_running) {
        return;  // Already stopped
    }
    
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
    
    // Dispatch to main thread for UI and emulator work
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([[EmulatorBridge sharedBridge] isROMLoaded]) {
            [[EmulatorBridge sharedBridge] runFrame];
        }
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

@end

#pragma clang diagnostic pop
