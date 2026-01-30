//
//  input_stubs.m
//  Red Viper - Virtual Boy Emulator for macOS
//
//  Real implementation of V810_RControll using InputManager
//

#import "InputManager.h"
#include "vb_dsp.h"

// Read controller state from InputManager
// Returns: 16-bit controller state
// Bit 0: Low battery flag (0 = OK)
// Bit 1: Battery status valid (1 = valid)
// Other bits: Button states (active high)
HWORD V810_RControll(bool reset) {
    (void)reset;  // Reset not needed for keyboard input
    return InputManager_currentControllerState();
}
