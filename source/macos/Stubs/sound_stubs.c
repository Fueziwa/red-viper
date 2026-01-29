//
//  sound_stubs.c
//  Red Viper - Virtual Boy Emulator for macOS
//
//  Stub implementations for vb_sound.h functions
//  These will be replaced with actual implementations in Phase 5 (Audio)
//

#include "vb_sound.h"
#include <string.h>

// Global sound state - required by core
SOUND_STATE sound_state;

void sound_init(void) {
    memset(&sound_state, 0, sizeof(sound_state));
}

void sound_update(uint32_t cycles) {
    (void)cycles;
}

void sound_write(int addr, uint16_t val) {
    (void)addr;
    (void)val;
}

void sound_refresh(void) {
}

void sound_close(void) {
}

void sound_pause(void) {
}

void sound_resume(void) {
}

void sound_reset(void) {
    memset(&sound_state, 0, sizeof(sound_state));
}
