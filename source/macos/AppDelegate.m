//
//  AppDelegate.m
//  Red Viper - Virtual Boy Emulator for macOS
//

#import "AppDelegate.h"
#import "MainWindow.h"
#import "EmulatorView.h"
#import "EmulatorBridge.h"
#import "ROMLoader.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    // Set up the main menu bar
    [self setupMainMenu];
    
    // Initialize the emulator core first
    [[EmulatorBridge sharedBridge] initialize];
    
    // Create the main window
    // Default to 2x scale (768x448) per user decision
    NSRect frame = NSMakeRect(0, 0, 768, 448);  // 2x Virtual Boy resolution (384x224)
    
    // Window is NOT resizable by dragging (fixed integer scales only)
    NSWindowStyleMask style = NSWindowStyleMaskTitled |
                              NSWindowStyleMaskClosable |
                              NSWindowStyleMaskMiniaturizable;
    
    self.window = [[NSWindow alloc] initWithContentRect:frame
                                              styleMask:style
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    
    [self.window setTitle:@"Red Viper"];
    [self.window center];
    
    // Create EmulatorView as the content view
    EmulatorView *emulatorView = [[EmulatorView alloc] initWithFrame:frame];
    [emulatorView setScale:2];  // Start at 2x scale
    [self.window setContentView:emulatorView];
    self.emulatorView = emulatorView;
    
    // Show the window
    [self.window makeKeyAndOrderFront:nil];
    
    // Activate the application
    [NSApp activateIgnoringOtherApps:YES];
    
    // Check for command-line ROM argument
    [self loadROMFromCommandLineIfPresent];
}

- (void)setupMainMenu {
    // Create the main menu bar
    NSMenu *mainMenu = [[NSMenu alloc] init];
    
    // App menu (Red Viper menu)
    NSMenuItem *appMenuItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:appMenuItem];
    
    NSMenu *appMenu = [[NSMenu alloc] init];
    [appMenu addItemWithTitle:@"About Red Viper" 
                       action:@selector(orderFrontStandardAboutPanel:) 
                keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Quit Red Viper" 
                       action:@selector(terminate:) 
                keyEquivalent:@"q"];
    [appMenuItem setSubmenu:appMenu];
    
    // File menu
    NSMenuItem *fileMenuItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:fileMenuItem];
    
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    
    NSMenuItem *openItem = [[NSMenuItem alloc] initWithTitle:@"Open..." 
                                                      action:@selector(openDocument:) 
                                               keyEquivalent:@"o"];
    [openItem setTarget:self];
    [fileMenu addItem:openItem];
    
    [fileMenu addItem:[NSMenuItem separatorItem]];
    
    [fileMenu addItemWithTitle:@"Close" 
                        action:@selector(performClose:) 
                 keyEquivalent:@"w"];
    
    [fileMenuItem setSubmenu:fileMenu];
    
    // Edit menu (for standard text editing shortcuts)
    NSMenuItem *editMenuItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:editMenuItem];
    
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [editMenu addItemWithTitle:@"Undo" action:@selector(undo:) keyEquivalent:@"z"];
    [editMenu addItemWithTitle:@"Redo" action:@selector(redo:) keyEquivalent:@"Z"];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    [editMenuItem setSubmenu:editMenu];
    
    // Window menu
    NSMenuItem *windowMenuItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:windowMenuItem];
    
    NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
    [windowMenu addItemWithTitle:@"Minimize" 
                          action:@selector(performMiniaturize:) 
                   keyEquivalent:@"m"];
    [windowMenu addItemWithTitle:@"Zoom" 
                          action:@selector(performZoom:) 
                   keyEquivalent:@""];
    [windowMenuItem setSubmenu:windowMenu];
    
    // Help menu
    NSMenuItem *helpMenuItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:helpMenuItem];
    
    NSMenu *helpMenu = [[NSMenu alloc] initWithTitle:@"Help"];
    [helpMenuItem setSubmenu:helpMenu];
    
    [NSApp setMainMenu:mainMenu];
    [NSApp setWindowsMenu:windowMenu];
    [NSApp setHelpMenu:helpMenu];
}

#pragma mark - ROM Loading

- (void)openDocument:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    
    [panel setTitle:@"Open ROM"];
    [panel setMessage:@"Select a Virtual Boy ROM file"];
    [panel setCanChooseFiles:YES];
    [panel setCanChooseDirectories:NO];
    [panel setAllowsMultipleSelection:NO];
    
    // Filter for .vb and .zip files
    [panel setAllowedContentTypes:@[
        [UTType typeWithFilenameExtension:@"vb"],
        [UTType typeWithFilenameExtension:@"zip"]
    ]];
    
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK) {
            NSURL *url = [[panel URLs] firstObject];
            if (url) {
                [self loadROMAtURL:url];
            }
        }
    }];
}

- (void)loadROMAtURL:(NSURL *)url {
    NSLog(@"AppDelegate: Loading ROM from URL: %@", url);
    
    NSError *error = nil;
    BOOL success = [[EmulatorBridge sharedBridge] loadROMAtPath:[url path] error:&error];
    
    if (!success) {
        NSLog(@"AppDelegate: Failed to load ROM: %@", error.localizedDescription);
        
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Failed to Load ROM"];
        [alert setInformativeText:error.localizedDescription ?: @"Unknown error"];
        [alert setAlertStyle:NSAlertStyleCritical];
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
    } else {
        // Update window title to show ROM name
        NSString *romName = [[url lastPathComponent] stringByDeletingPathExtension];
        [self.window setTitle:[NSString stringWithFormat:@"Red Viper - %@", romName]];
    }
}

- (void)loadROMFromCommandLineIfPresent {
    NSArray *args = [[NSProcessInfo processInfo] arguments];
    
    // Skip first argument (path to executable)
    // Look for ROM path argument
    for (NSUInteger i = 1; i < args.count; i++) {
        NSString *arg = args[i];
        
        // Skip flags
        if ([arg hasPrefix:@"-"]) {
            continue;
        }
        
        // Check if it looks like a ROM file
        NSString *ext = [[arg pathExtension] lowercaseString];
        if ([ext isEqualToString:@"vb"] || [ext isEqualToString:@"zip"]) {
            NSLog(@"AppDelegate: Found ROM in command line arguments: %@", arg);
            
            // Delay loading slightly to ensure window is ready
            dispatch_async(dispatch_get_main_queue(), ^{
                NSURL *url = [NSURL fileURLWithPath:arg];
                [self loadROMAtURL:url];
            });
            break;
        }
    }
}

#pragma mark - Application Lifecycle

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    // Clean up extracted ROM files
    [[ROMLoader sharedLoader] cleanup];
    
    // Shutdown the emulator core
    [[EmulatorBridge sharedBridge] shutdown];
}

- (BOOL)application:(NSApplication *)sender openFile:(NSString *)filename {
    // Handle drag-and-drop or double-click on ROM file
    NSLog(@"AppDelegate: Opening file: %@", filename);
    
    NSURL *url = [NSURL fileURLWithPath:filename];
    [self loadROMAtURL:url];
    
    return YES;
}

@end
