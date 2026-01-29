//
//  drc_stubs.c
//  Red Viper - Virtual Boy Emulator for macOS
//
//  Stub implementations for DRC (Dynamic Recompiler) functions
//  DRC is ARM-specific and not available on macOS - we use interpreter mode only
//

#include "drc_core.h"
#include "v810_mem.h"
#include <stdlib.h>

// Global DRC state - required by core even when DRC is disabled
WORD* cache_start = NULL;
WORD* cache_pos = NULL;

void drc_init(void) {
    // No-op on macOS - DRC not available
}

void drc_reset(void) {
    // No-op on macOS - DRC not available
}

void drc_exit(void) {
    // No-op on macOS - DRC not available
}

int drc_run(void) {
    // Return error indicating DRC is not available
    // Core will fall back to interpreter mode
    return DRC_ERR_NO_DYNAREC;
}

void drc_clearCache(void) {
    // No-op on macOS - DRC not available
}

int drc_handleInterrupts(WORD cpsr, WORD* PC) {
    (void)cpsr;
    (void)PC;
    // No-op on macOS - interrupts handled by interpreter
    return 0;
}

void drc_relocTable(void) {
    // No-op on macOS - DRC not available
}

void drc_loadSavedCache(void) {
    // No-op on macOS - DRC not available
}

void drc_dumpCache(char* filename) {
    (void)filename;
    // No-op on macOS - DRC not available
}

void drc_dumpDebugInfo(int code) {
    (void)code;
    // No-op on macOS - DRC not available
}

void drc_setEntry(WORD loc, WORD *entry, exec_block *block) {
    (void)loc;
    (void)entry;
    (void)block;
    // No-op on macOS - DRC not available
}

exec_block* drc_getNextBlockStruct(void) {
    // Return NULL - DRC not available
    return NULL;
}

void drc_executeBlock(WORD* entrypoint, exec_block* block) {
    (void)entrypoint;
    (void)block;
    // No-op on macOS - DRC not available
}
