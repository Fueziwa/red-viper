//
//  display_stubs.c
//  Red Viper - Virtual Boy Emulator for macOS
//
//  Stub implementations for vb_dsp.h functions
//  These will be replaced with actual implementations in Phase 2 (Video Rendering)
//

#include "vb_dsp.h"
#include "v810_mem.h"
#include <string.h>

// Global display cache - required by core
VB_DSPCACHE tDSPCACHE;

// Note: tileVisible, blankTile, and clearCache are defined in video_common.c

// Additional globals from vb_dsp.h
uint8_t maxRepeat = 1;
int eye_count = 1;

// Display functions - stub implementations
void video_init(void) {
    memset(&tDSPCACHE, 0, sizeof(tDSPCACHE));
}

void video_render(int displayed_fb, bool on_time) {
    (void)displayed_fb;
    (void)on_time;
}

void video_flush(bool left_for_both) {
    (void)left_for_both;
}

void video_quit(void) {
}

void V810_SetPal(int BRTA, int BRTB, int BRTC) {
    (void)BRTA;
    (void)BRTB;
    (void)BRTC;
}

void V810_Dsp_Frame(int left) {
    (void)left;
}

// Software rendering stubs - also required by core
void video_soft_render(int drawn_fb) {
    (void)drawn_fb;
}

void update_texture_cache_soft(void) {
}
