//
//  vb_sound_macos.c
//  Red Viper - Virtual Boy Emulator for macOS
//
//  Virtual Boy audio synthesis and playback using macOS Audio Queue Services.
//  Ported from source/3ds/vb_sound.c - synthesis logic preserved, 3DS NDSP replaced with Audio Queue.
//

#include <AudioToolbox/AudioToolbox.h>
#include <string.h>
#include <stdlib.h>

#include "v810_mem.h"
#include "vb_set.h"
#include "vb_sound.h"

// Sample rate adjusted for macOS (48kHz is standard)
#define SAMPLE_RATE 48000
#define CYCLES_PER_SAMPLE (20000000 / SAMPLE_RATE)
#define SAMPLE_COUNT (SAMPLE_RATE / 100)
#define BUF_COUNT 9

// Global sound state
SOUND_STATE sound_state;

// Static state for synthesis
static int constant_sample[5] = {-1, -1, -1, -1, -1};
static bool changed_sample[5] = {0};

static uint8_t fill_buf = 0;
static uint8_t play_buf = 0;
static uint16_t buf_pos = 0;

static volatile bool paused = false;
static bool muted = false;

static const int noise_bits[8] = {14, 10, 13, 4, 8, 6, 9, 11};

static short dc_offset = 0;

// Audio Queue components
static AudioQueueRef audioQueue = NULL;
static AudioQueueBufferRef audioBuffers[BUF_COUNT];
static int16_t *bufferData[BUF_COUNT];
static bool audioInitialized = false;

// Buffer synchronization: tracks which buffers are ready for playback
// false = buffer is free (consumer done or not yet filled)
// true = buffer is filled and ready for consumer
static volatile bool bufferReady[BUF_COUNT] = {0};

// Macros for sound memory access (from 3DS version)
#define SNDMEM(x) (vb_state->V810_SOUND_RAM.pmemory[(x) & 0xFFF])
#define GET_FREQ(ch) ((SNDMEM(S1FQL + 0x40 * ch) | (SNDMEM(S1FQH + 0x40 * ch) << 8)) & 0x7ff)
#define GET_FREQ_TIME(ch) ( \
    (2048 - (ch != 4 ? GET_FREQ(ch) : sound_state.sweep_frequency)) \
    * (ch == 5 ? 40 : 4))

// Forward declaration for callback
static void audioQueueCallback(void *userData, AudioQueueRef queue, AudioQueueBufferRef buffer);

// Fill buffer with a single sample for one channel
static void fill_buf_single_sample(int ch, int samples, int offset) {
    ChannelState *channel = &sound_state.channels[ch];
    int lrv = SNDMEM(S1LRV + 0x40 * ch);
    int left_vol = (channel->envelope_value * (lrv >> 4)) >> 3;
    int right_vol = (channel->envelope_value * (lrv & 0xf)) >> 3;
    if (channel->envelope_value != 0) {
        // if neither stereo nor envelope is 0, increment amplitude
        if (lrv & 0xf0) left_vol++;
        if (lrv & 0x0f) right_vol++;
    }
    uint8_t sample;
    if (ch < 5) {
        sample = SNDMEM(0x80 * (SNDMEM(S1RAM + 0x40 * ch) & 7) + 4 * channel->sample_pos) & 63;
    } else {
        int bit = ~(sound_state.noise_shift >> 7);
        bit ^= sound_state.noise_shift >> noise_bits[(SNDMEM(S6EV1) >> 4) & 7];
        sample = (bit & 1) ? 0x3f : 0x00;
    }
    uint32_t total = ((left_vol * sample) & 0xffff) | ((right_vol * sample) << 16);
    for (int i = 0; i < samples; i++) {
        ((uint32_t*)(bufferData[fill_buf]))[offset + i] += total;
    }
}

// Update buffer with frequency modulation for a channel
static void update_buf_with_freq(int ch, int samples) {
    if (!(SNDMEM(S1INT + 0x40 * ch) & 0x80)) return;
    if (sound_state.channels[ch].envelope_value == 0) return;
    if (ch < 5 && (SNDMEM(S1RAM + 0x40 * ch) & 7) >= 5) return;
    if (!tVBOpt.SOUND) return;
    int total_clocks = samples * CYCLES_PER_SAMPLE;
    int current_clocks = 0;
    int freq_time = GET_FREQ_TIME(ch);
    while (current_clocks < total_clocks) {
        int clocks = total_clocks - current_clocks;
        // optimization for constant samples
        if (ch == 5 || constant_sample[SNDMEM(S1RAM + 0x40 * ch) & 7] < 0) {
            if (clocks > sound_state.channels[ch].freq_time)
                clocks = sound_state.channels[ch].freq_time;
        } else {
            // constant sample, just reset the freqtime
            sound_state.channels[ch].freq_time = clocks + freq_time;
        }
        int current_samples = current_clocks / CYCLES_PER_SAMPLE;
        int next_samples = (current_clocks + clocks) / CYCLES_PER_SAMPLE;
        fill_buf_single_sample(ch, next_samples - current_samples, buf_pos + current_samples);
        if ((sound_state.channels[ch].freq_time -= clocks) == 0) {
            if (ch < 5) {
                sound_state.channels[ch].sample_pos += 1;
                sound_state.channels[ch].sample_pos &= 31;
            } else {
                int bit = ~(sound_state.noise_shift >> 7);
                bit ^= sound_state.noise_shift >> noise_bits[(SNDMEM(S6EV1) >> 4) & 7];
                sound_state.noise_shift = (sound_state.noise_shift << 1) | (bit & 1);
            }
            sound_state.channels[ch].freq_time = freq_time;
        }
        current_clocks += clocks;
    }
}

// Main synthesis function - called from CPU loop
void sound_update(uint32_t cycles) {
    if (!emulating_self) return;
    if (!audioInitialized) return;
    
    int remaining_samples = (cycles - sound_state.last_cycles) / CYCLES_PER_SAMPLE;
    if (remaining_samples <= 0) return;
    sound_state.last_cycles += remaining_samples * CYCLES_PER_SAMPLE;
    
    while (remaining_samples > 0) {
        int samples = remaining_samples;
        if (samples > SAMPLE_COUNT - buf_pos)
            samples = SAMPLE_COUNT - buf_pos;
        if (samples > sound_state.effect_time)
            samples = sound_state.effect_time;
        memset(bufferData[fill_buf] + buf_pos * 2, 0, sizeof(int16_t) * samples * 2);

        for (int i = 0; i < 6; i++) {
            update_buf_with_freq(i, samples);
        }

        if ((sound_state.effect_time -= samples) == 0) {
            sound_state.effect_time = 48;
            // sweep
            if (SNDMEM(S5INT) & 0x80) {
                // early sweep frequency and shutoff
                int env = SNDMEM(S5EV1);
                int swp = SNDMEM(S5SWP);
                int new_sweep_frequency = sound_state.sweep_frequency;
                if (!(env & 0x10)) {
                    int shift = swp & 0x7;
                    if (swp & 8) {
                        new_sweep_frequency += sound_state.sweep_frequency >> shift;
                        if (new_sweep_frequency >= 2048) SNDMEM(S5INT) = 0;
                    } else {
                        new_sweep_frequency -= sound_state.sweep_frequency >> shift;
                        if (new_sweep_frequency < 0) new_sweep_frequency = 0;
                    }
                }
                if ((env & 0x40) && --sound_state.sweep_time < 0) {
                    int swp_inner = SNDMEM(S5SWP);
                    int interval = (swp_inner >> 4) & 7;
                    sound_state.sweep_time = interval * ((swp_inner & 0x80) ? 8 : 1);
                    if (sound_state.sweep_time != 0) {
                        if (env & 0x10) {
                            // modulation
                            // only enable on first loop or if repeat
                            if (sound_state.modulation_state == 0 || (env & 0x20)) {
                                sound_state.sweep_frequency = GET_FREQ(4) + (int8_t)SNDMEM(MODDATA + 4 * sound_state.modulation_counter);
                            }
                            if (sound_state.modulation_state == 1) sound_state.modulation_state = 2;
                            // hardware bug: writing to S5FQ* locks the relevant byte when modulating
                            if (sound_state.modulation_lock == 1) {
                                sound_state.sweep_frequency = (sound_state.sweep_frequency & 0x700) | SNDMEM(S5FQL);
                            } else if (sound_state.modulation_lock == 2) {
                                sound_state.sweep_frequency = (sound_state.sweep_frequency & 0xff) | (SNDMEM(S5FQH) << 8);
                            }
                            sound_state.sweep_frequency &= 0x7ff;
                        } else if (sound_state.modulation_state < 2) {
                            // sweep using previous calculation
                            sound_state.sweep_frequency = new_sweep_frequency;
                        }
                        if (++sound_state.modulation_counter >= 32) {
                            if (sound_state.modulation_state == 0) sound_state.modulation_state = 1;
                            sound_state.modulation_counter = 0;
                        }
                    }
                }
            }
            
            // shutoff
            if (--sound_state.shutoff_divider >= 0) goto effects_done;
            sound_state.shutoff_divider += 4;
            for (int i = 0; i < 6; i++) {
                int data = SNDMEM(S1INT + 0x40 * i);
                if ((data & 0xa0) == 0xa0) {
                    if ((--sound_state.channels[i].shutoff_time & 0x1f) == 0x1f) {
                        SNDMEM(S1INT + 0x40 * i) &= ~0x80;
                    }
                }
            }

            // envelope
            if (--sound_state.envelope_divider >= 0) goto effects_done;
            sound_state.envelope_divider += 4;
            for (int i = 0; i < 6; i++) {
                if (!(SNDMEM(S1INT + 0x40 * i) & 0x80)) continue;
                int data1 = SNDMEM(S1EV1 + 0x40 * i);
                if ((data1 & 1) && !(sound_state.channels[i].envelope_time & 128)) {
                    if (--sound_state.channels[i].envelope_time & 8) {
                        int data0 = SNDMEM(S1EV0 + 0x40 * i);
                        sound_state.channels[i].envelope_time = data0 & 7;
                        sound_state.channels[i].envelope_value += (data0 & 8) ? 1 : -1;
                        if (sound_state.channels[i].envelope_value & 0x10) {
                            if (data1 & 2) {
                                sound_state.channels[i].envelope_value = data0 >> 4;
                            } else {
                                sound_state.channels[i].envelope_value -= (data0 & 8) ? 1 : -1;
                                sound_state.channels[i].envelope_time = 128;
                            }
                        }
                    }
                }
            }
        }
        effects_done:
        buf_pos += samples;
        remaining_samples -= samples;
        if (buf_pos == SAMPLE_COUNT) {
            // final post processing
            for (int i = 0; i < SAMPLE_COUNT; i++) {
                #define AMPLIFY(x) (((x) >> 4) * 95)
                short left = AMPLIFY(bufferData[fill_buf][i * 2]) + dc_offset;
                short right = AMPLIFY(bufferData[fill_buf][i * 2 + 1]) + dc_offset;
                #undef AMPLIFY
                int extra_offset = dc_offset - (-left - right + dc_offset * 48) / 50;
                if (left < dc_offset || right < dc_offset) {
                    int extra_offset_inner = 0;
                    if (left < dc_offset)
                        extra_offset_inner = left - 0x7fff;
                    if (right < dc_offset && right - 0x7fff > extra_offset_inner)
                        extra_offset_inner = right - 0x7fff;
                    extra_offset = extra_offset_inner;
                }
                left -= extra_offset;
                right -= extra_offset;
                dc_offset -= extra_offset;
                if (dc_offset != 0) {
                    bufferData[fill_buf][i * 2] = left;
                    bufferData[fill_buf][i * 2 + 1] = right;
                }
            }
            // Mark buffer as ready for consumer
            bufferReady[fill_buf] = true;
            
            // Move to next buffer only if it's free (consumer has consumed it)
            uint8_t next_buf = (fill_buf + 1) % BUF_COUNT;
            if (!bufferReady[next_buf]) {
                fill_buf = next_buf;
            }
            // If next buffer not free, we'll overwrite current buffer on next call
            // This drops audio rather than corrupting playback timing
            buf_pos = 0;
        }
    }
}

// Handle writes to sound registers
void sound_write(int addr, uint16_t data) {
    if (!emulating_self) return;
    if (addr & 1) return;
    addr &= ~2;
    sound_state.modulation_lock = 0;
    if (!(addr & 0x400)) {
        // ram writes, these can be declined
        // all ram writes are declined if channel 5 is active
        if (SNDMEM(S5INT) & 0x80) return;
        if ((addr & 0x370) < 0x280) {
            // wave ram is declined if any channel is active
            if ((SNDMEM(S1INT) & 0x80) ||
                (SNDMEM(S2INT) & 0x80) ||
                (SNDMEM(S3INT) & 0x80) ||
                (SNDMEM(S4INT) & 0x80) ||
                (SNDMEM(S6INT) & 0x80)) return;
            changed_sample[(addr >> 7) & 7] = true;
        }
    } else if ((addr & 0x7ff) <= 0x580) {
        sound_update(vb_state->v810_state.cycles);
    }
    bool was_silent = false;
    if ((addr & 0x3f) == (S1INT & 0x3f)) {
        was_silent =
            !(SNDMEM(S1INT) & 0x80) && !(SNDMEM(S2INT) & 0x80) &&
            !(SNDMEM(S3INT) & 0x80) && !(SNDMEM(S4INT) & 0x80) &&
            !(SNDMEM(S5INT) & 0x80) && !(SNDMEM(S6INT) & 0x80);
    }
    SNDMEM(addr) = data;
    int ch = (addr >> 6) & 7;
    if (addr < 0x01000400) {
        // ignore
    } else if (addr == SSTOP) {
        if (data & 1) {
            for (int i = 0; i < 6; i++) {
                SNDMEM(S1INT + 0x40 * i) &= ~0x80;
            }
        }
    } else if ((addr & 0x3f) == (S1INT & 0x3f)) {
        if (was_silent) {
            // just turned on audio, so check for static samples
            for (int sample = 0; sample < 5; sample++) {
                if (changed_sample[sample]) {
                    constant_sample[sample] = SNDMEM(0x80 * sample);
                    for (int i = 1; i < 32; i++) {
                        if (SNDMEM(0x80 * sample + 4 * i) != constant_sample[sample]) {
                            constant_sample[sample] = -1;
                            break;
                        }
                    }
                    changed_sample[sample] = false;
                }
            }
        }
        if (ch == 4) {
            // sweep/modulation
            int swp = SNDMEM(S5SWP);
            int interval = (swp >> 4) & 7;
            sound_state.sweep_time = interval * ((swp & 0x80) ? 8 : 1);
            sound_state.modulation_counter = 0;
            sound_state.modulation_state = 0;
        } else if (ch == 5) {
            sound_state.noise_shift = 0;
        }
        sound_state.channels[ch].shutoff_time = data & 0x1f;
        sound_state.channels[ch].sample_pos = 0;
        sound_state.channels[ch].freq_time = GET_FREQ_TIME(ch);
        int ev0 = SNDMEM(S1EV0 + 0x40 * ch);
        sound_state.channels[ch].envelope_time = ev0 & 7;
    } else if ((addr & 0x3f) == (S1EV0 & 0x3f)) {
        sound_state.channels[ch].envelope_value = (data >> 4) & 0xf;
    } else if (addr == S5FQL) {
        ((uint8_t*)&sound_state.sweep_frequency)[0] = data;
        if (SNDMEM(S5EV1) & 0x10) sound_state.modulation_lock = 1;
    } else if (addr == S5FQH) {
        ((uint8_t*)&sound_state.sweep_frequency)[1] = data & 0x7;
        if (SNDMEM(S5EV1) & 0x10) sound_state.modulation_lock = 2;
    } else if (addr == S6EV1) {
        sound_state.noise_shift = 0;
    }
}

// Refresh sample state
void sound_refresh(void) {
    for (int sample = 0; sample < 5; sample++) {
        changed_sample[sample] = false;
        constant_sample[sample] = SNDMEM(0x80 * sample);
        for (int i = 1; i < 32; i++) {
            if (SNDMEM(0x80 * sample + 4 * i) != constant_sample[sample]) {
                constant_sample[sample] = -1;
                break;
            }
        }
    }
    for (int i = 0; i < BUF_COUNT; i++) {
        if (bufferData[i]) {
            memset(bufferData[i], 0, SAMPLE_COUNT * 4);
        }
        bufferReady[i] = false;
    }
    fill_buf = 0;
    play_buf = 0;
    buf_pos = 0;
    paused = false;
}

// Audio Queue callback - runs on audio thread
static void audioQueueCallback(void *userData, AudioQueueRef queue, AudioQueueBufferRef buffer) {
    (void)userData;
    
    if (paused || !audioInitialized) {
        // Fill with silence when paused
        memset(buffer->mAudioData, 0, SAMPLE_COUNT * 4);
    } else {
        // Check if the next buffer in sequence is ready
        if (bufferReady[play_buf] && bufferData[play_buf]) {
            // Copy synthesized audio to the Audio Queue buffer
            memcpy(buffer->mAudioData, bufferData[play_buf], SAMPLE_COUNT * 4);
            // Mark buffer as consumed (free for producer)
            bufferReady[play_buf] = false;
            // Advance consumer index
            play_buf = (play_buf + 1) % BUF_COUNT;
        } else {
            // Buffer not ready - play silence to maintain timing
            // This is an underrun condition
            memset(buffer->mAudioData, 0, SAMPLE_COUNT * 4);
        }
    }
    
    buffer->mAudioDataByteSize = SAMPLE_COUNT * 4;
    AudioQueueEnqueueBuffer(queue, buffer, 0, NULL);
}

// Initialize audio system
void sound_init(void) {
    memset(&sound_state, 0, sizeof(sound_state));
    fill_buf = 0;
    play_buf = 0;
    buf_pos = 0;
    for (int i = 0; i < BUF_COUNT; i++) {
        bufferReady[i] = false;
    }
    
    // Audio format: stereo 16-bit PCM at 48kHz
    AudioStreamBasicDescription desc = {
        .mSampleRate = SAMPLE_RATE,
        .mFormatID = kAudioFormatLinearPCM,
        .mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
        .mBitsPerChannel = 16,
        .mChannelsPerFrame = 2,
        .mBytesPerFrame = 4,
        .mFramesPerPacket = 1,
        .mBytesPerPacket = 4
    };
    
    // Create audio queue
    OSStatus status = AudioQueueNewOutput(&desc, audioQueueCallback, NULL, NULL, NULL, 0, &audioQueue);
    if (status != noErr) {
        tVBOpt.SOUND = 0;
        return;
    }
    
    // Allocate buffers
    for (int i = 0; i < BUF_COUNT; i++) {
        status = AudioQueueAllocateBuffer(audioQueue, SAMPLE_COUNT * 4, &audioBuffers[i]);
        if (status != noErr) {
            AudioQueueDispose(audioQueue, true);
            audioQueue = NULL;
            tVBOpt.SOUND = 0;
            return;
        }
        
        // Allocate synthesis buffer
        bufferData[i] = calloc(SAMPLE_COUNT * 2, sizeof(int16_t));
        if (!bufferData[i]) {
            AudioQueueDispose(audioQueue, true);
            audioQueue = NULL;
            tVBOpt.SOUND = 0;
            return;
        }
        
        // Prime with silence and enqueue
        memset(audioBuffers[i]->mAudioData, 0, SAMPLE_COUNT * 4);
        audioBuffers[i]->mAudioDataByteSize = SAMPLE_COUNT * 4;
        AudioQueueEnqueueBuffer(audioQueue, audioBuffers[i], 0, NULL);
    }
    
    // Set volume to 1.0 and ensure unmuted state
    AudioQueueSetParameter(audioQueue, kAudioQueueParam_Volume, 1.0);
    muted = false;
    
    // Start playback
    status = AudioQueueStart(audioQueue, NULL);
    if (status != noErr) {
        for (int i = 0; i < BUF_COUNT; i++) {
            if (bufferData[i]) {
                free(bufferData[i]);
                bufferData[i] = NULL;
            }
        }
        AudioQueueDispose(audioQueue, true);
        audioQueue = NULL;
        tVBOpt.SOUND = 0;
        return;
    }
    
    audioInitialized = true;
}

// Close audio system
void sound_close(void) {
    if (audioQueue) {
        AudioQueueStop(audioQueue, true);
        AudioQueueDispose(audioQueue, true);
        audioQueue = NULL;
    }
    
    for (int i = 0; i < BUF_COUNT; i++) {
        if (bufferData[i]) {
            free(bufferData[i]);
            bufferData[i] = NULL;
        }
        audioBuffers[i] = NULL;
    }
    
    audioInitialized = false;
}

// Pause audio playback
void sound_pause(void) {
    paused = true;
    dc_offset = 0;
    if (audioQueue) {
        AudioQueuePause(audioQueue);
    }
}

// Resume audio playback
void sound_resume(void) {
    paused = false;
    if (audioQueue) {
        AudioQueueStart(audioQueue, NULL);
    }
}

// Reset sound state
void sound_reset(void) {
    memset(&sound_state, 0, sizeof(sound_state));
    for (int i = 0; i < 6; i++) {
        SNDMEM(S1INT + 0x40 * i) = 0;
    }
    fill_buf = 0;
    play_buf = 0;
    buf_pos = 0;
    for (int i = 0; i < BUF_COUNT; i++) {
        bufferReady[i] = false;
    }
    sound_refresh();
}

// Toggle mute state
void sound_toggle_mute(void) {
    muted = !muted;
    if (audioQueue) {
        AudioQueueSetParameter(audioQueue, kAudioQueueParam_Volume, muted ? 0.0 : 1.0);
    }
}

// Query mute state
bool sound_is_muted(void) {
    return muted;
}
