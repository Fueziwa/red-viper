//
//  input_stubs.c
//  Red Viper - Virtual Boy Emulator for macOS
//
//  Stub implementation for V810_RControll
//  This will be replaced with actual input handling in Phase 3 (Keyboard Input)
//

#include "vb_dsp.h"

// Read controller state
// Returns: 16-bit controller state
// Bit 0: Low battery flag (0 = OK)
// Bit 1: Battery status valid (1 = valid)
// Other bits: Button states (active high)
HWORD V810_RControll(bool reset) {
    (void)reset;
    // Return "battery OK, no buttons pressed"
    // Bit 1 set = battery status valid, bit 0 clear = battery OK
    return 0x0002;
}
