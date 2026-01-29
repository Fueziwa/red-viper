//
//  MainWindow.m
//  Red Viper - Virtual Boy Emulator for macOS
//

#import "MainWindow.h"

@implementation MainWindow

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        // Set up as layer-backed view for proper rendering
        [self setWantsLayer:YES];
        self.layer.backgroundColor = [[NSColor blackColor] CGColor];
    }
    return self;
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    
    // Fill with black background
    [[NSColor blackColor] setFill];
    NSRectFill(dirtyRect);
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

@end
