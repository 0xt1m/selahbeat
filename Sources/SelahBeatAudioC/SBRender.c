//
//  SBRender.c — the real-time render path.
//
//  See THE RULE in SBAudio.h. Nothing here allocates, locks, or blocks.
//

#include "include/SBAudio.h"

#include <string.h>
#include <stdlib.h>
#include <math.h>
#include <mach/mach_time.h>
#include <time.h>

// MARK: - Float <-> bits (avoids _Atomic float portability quirks)

static inline uint32_t sb_float_bits(float f) {
    uint32_t b;
    memcpy(&b, &f, sizeof(b));
    return b;
}

static inline float sb_bits_float(uint32_t b) {
    float f;
    memcpy(&f, &b, sizeof(f));
    return f;
}

// MARK: - Lifecycle

SBEngineState *sb_engine_create(double sampleRate) {
    SBEngineState *st = (SBEngineState *)calloc(1, sizeof(SBEngineState));
    if (!st) return NULL;

    st->scratch = (float *)calloc(SB_MAX_RENDER_FRAMES, sizeof(float));
    if (!st->scratch) {
        free(st);
        return NULL;
    }

    st->sampleRate = (sampleRate > 0.0) ? sampleRate : 48000.0;

    // Host time base: mHostTime ticks -> nanoseconds is (numer/denom).
    mach_timebase_info_data_t tb;
    if (mach_timebase_info(&tb) != KERN_SUCCESS || tb.numer == 0) {
        tb.numer = 1;
        tb.denom = 1;
    }
    st->hostTicksPerSecond = 1.0e9 * (double)tb.denom / (double)tb.numer;

    atomic_store_explicit(&st->running, 0, memory_order_relaxed);
    atomic_store_explicit(&st->runToken, 0, memory_order_relaxed);
    atomic_store_explicit(&st->masterGainBits, sb_float_bits(1.0f), memory_order_relaxed);
    atomic_store_explicit(&st->previewLevel, -1, memory_order_relaxed);
    atomic_store_explicit(&st->liveSlot, 0, memory_order_relaxed);

    st->writerNextSlot = 1;
    st->writerPrevSlot = 0;
    st->writerGeneration = 0;

    // Slot 0 is a valid but silent default: 120 BPM, 4/4, no sounds loaded yet.
    st->slots[0].framesPerTick = st->sampleRate * 60.0 / 120.0;
    st->slots[0].ticksPerBar = 4;
    st->slots[0].ticksPerBeat = 1;
    st->slots[0].pattern[0] = SB_LEVEL_DOWNBEAT;
    st->slots[0].pattern[1] = SB_LEVEL_QUARTER;
    st->slots[0].pattern[2] = SB_LEVEL_QUARTER;
    st->slots[0].pattern[3] = SB_LEVEL_QUARTER;
    for (int i = 0; i < SB_ACCENT_LEVELS; i++) st->slots[0].levelGain[i] = 1.0f;
    st->slots[0].generation = 0;

    st->framesPerTick = st->slots[0].framesPerTick;
    st->ticksPerBar = 4;
    st->lastParamsGeneration = 0;

    return st;
}

void sb_engine_destroy(SBEngineState *st) {
    if (!st) return;
    free(st->scratch);
    free(st);
}

void sb_engine_set_sample_rate(SBEngineState *st, double sampleRate) {
    if (!st || sampleRate <= 0.0) return;
    // Stop first: the caller is required to re-render the bank and re-publish
    // params, and a live voice pointing at the old arena must not survive.
    sb_stop(st);
    st->sampleRate = sampleRate;
    for (int i = 0; i < SB_MAX_VOICES; i++) {
        st->voices[i].active = 0;
        st->voices[i].samples = NULL;
    }
}

// MARK: - Transport

void sb_start(SBEngineState *st) {
    if (!st) return;
    // Order matters: publish the new token before flipping running, so the
    // render thread can never see running==1 with a stale token.
    atomic_fetch_add_explicit(&st->runToken, 1, memory_order_release);
    atomic_store_explicit(&st->running, 1, memory_order_release);
}

void sb_stop(SBEngineState *st) {
    if (!st) return;
    atomic_store_explicit(&st->running, 0, memory_order_release);
}

bool sb_is_running(const SBEngineState *st) {
    if (!st) return false;
    return atomic_load_explicit(&st->running, memory_order_acquire) != 0;
}

void sb_set_master_gain(SBEngineState *st, float gain) {
    if (!st) return;
    if (gain < 0.0f) gain = 0.0f;
    if (gain > 4.0f) gain = 4.0f;
    atomic_store_explicit(&st->masterGainBits, sb_float_bits(gain), memory_order_release);
}

void sb_preview(SBEngineState *st, int32_t level) {
    if (!st) return;
    if (level < 0 || level >= SB_ACCENT_LEVELS) return;
    atomic_store_explicit(&st->previewLevel, level, memory_order_release);
}

// MARK: - Parameter publish (single producer)

void sb_publish_params(SBEngineState *st,
                       double framesPerTick,
                       uint32_t ticksPerBar,
                       uint32_t ticksPerBeat,
                       const uint8_t *pattern,
                       const SBSoundRef *sounds,
                       const float *levelGain) {
    if (!st) return;
    if (ticksPerBar == 0 || ticksPerBar > SB_MAX_TICKS_PER_BAR) return;
    if (!(framesPerTick > 1.0) || !isfinite(framesPerTick)) return;

    int32_t slot = st->writerNextSlot;
    SBClickParams *p = &st->slots[slot];

    p->framesPerTick = framesPerTick;
    p->ticksPerBar = ticksPerBar;
    p->ticksPerBeat = (ticksPerBeat == 0) ? 1 : ticksPerBeat;

    memset(p->pattern, 0, sizeof(p->pattern));
    if (pattern) {
        for (uint32_t i = 0; i < ticksPerBar; i++) {
            uint8_t lvl = pattern[i];
            p->pattern[i] = (lvl < SB_ACCENT_LEVELS) ? lvl : (uint8_t)SB_LEVEL_SILENT;
        }
    }

    for (int i = 0; i < SB_ACCENT_LEVELS; i++) {
        p->sounds[i] = sounds ? sounds[i] : (SBSoundRef){ NULL, 0, 0.0f };
        float g = levelGain ? levelGain[i] : 1.0f;
        if (!(g >= 0.0f)) g = 0.0f;      // also rejects NaN
        if (g > 2.0f) g = 2.0f;
        p->levelGain[i] = g;
    }

    p->generation = ++st->writerGeneration;

    // Publish, then pick a slot that is neither the one we just published nor
    // the one before it — so the reader is never mid-read of our next target.
    atomic_store_explicit(&st->liveSlot, slot, memory_order_release);

    int32_t next = (slot + 1) % SB_PARAM_SLOTS;
    if (next == st->writerPrevSlot) next = (next + 1) % SB_PARAM_SLOTS;
    st->writerPrevSlot = slot;
    st->writerNextSlot = next;
}

/// What a tick is musically, from its position inside the beat.
///
/// Used as the fallback when the accent bus is muted: silencing the accent must
/// not leave a hole in the pulse, it should leave the underlying note sounding.
static inline uint8_t sb_natural_level(uint32_t tickInBar, uint32_t ticksPerBeat) {
    if (ticksPerBeat <= 1) return SB_LEVEL_QUARTER;
    uint32_t pos = tickInBar % ticksPerBeat;
    if (pos == 0) return SB_LEVEL_QUARTER;
    if (ticksPerBeat == 4) return (pos == 2) ? SB_LEVEL_EIGHTH : SB_LEVEL_SIXTEENTH;
    return SB_LEVEL_EIGHTH;
}

// MARK: - Voices

static inline void sb_mix_voice(SBEngineState *st,
                                SBVoice *v,
                                uint32_t startFrame,
                                uint32_t frameCount) {
    if (!v->active || !v->samples) return;
    if (startFrame >= frameCount) return;

    uint32_t avail = (v->cursor < v->length) ? (v->length - v->cursor) : 0;
    uint32_t room = frameCount - startFrame;
    uint32_t n = (avail < room) ? avail : room;

    const float *src = v->samples + v->cursor;
    float *dst = st->scratch + startFrame;
    const float g = v->gain;

    for (uint32_t i = 0; i < n; i++) {
        dst[i] += src[i] * g;
    }

    v->cursor += n;
    if (v->cursor >= v->length) {
        v->active = 0;
        v->samples = NULL;
    }
}

/// Claims a voice slot for `snd`. Steals the oldest if all are busy.
/// Returns NULL if the sound is empty.
static inline SBVoice *sb_trigger(SBEngineState *st, const SBSoundRef *snd, float busGain) {
    if (!snd || !snd->samples || snd->length == 0) return NULL;
    if (busGain <= 0.0f) return NULL;   // a muted bus costs no voice at all

    int32_t idx = -1;
    for (int i = 0; i < SB_MAX_VOICES; i++) {
        if (!st->voices[i].active) { idx = i; break; }
    }
    if (idx < 0) {
        uint64_t oldest = UINT64_MAX;
        idx = 0;
        for (int i = 0; i < SB_MAX_VOICES; i++) {
            if (st->voices[i].order < oldest) {
                oldest = st->voices[i].order;
                idx = i;
            }
        }
    }

    SBVoice *v = &st->voices[idx];
    v->samples = snd->samples;
    v->length = snd->length;
    v->gain = snd->gain * busGain;
    v->cursor = 0;
    v->active = 1;
    v->order = ++st->voiceOrderCounter;
    return v;
}

// MARK: - Render

OSStatus sb_render(SBEngineState *st,
                   const AudioTimeStamp *ts,
                   uint32_t frameCount,
                   AudioBufferList *abl) {
    if (!st || !abl) return kAudio_ParamError;

    const uint64_t t0 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);

    if (frameCount == 0) return noErr;
    if (frameCount > SB_MAX_RENDER_FRAMES) {
        // Refuse rather than overrun. Output silence and flag it.
        atomic_fetch_add_explicit(&st->underrunCount, 1, memory_order_relaxed);
        for (UInt32 b = 0; b < abl->mNumberBuffers; b++) {
            if (abl->mBuffers[b].mData) {
                memset(abl->mBuffers[b].mData, 0, abl->mBuffers[b].mDataByteSize);
            }
        }
        return noErr;
    }

    memset(st->scratch, 0, (size_t)frameCount * sizeof(float));

    // --- Read shared state once ---
    const int32_t running = atomic_load_explicit(&st->running, memory_order_acquire);
    const uint64_t token = atomic_load_explicit(&st->runToken, memory_order_acquire);
    const int32_t slot = atomic_load_explicit(&st->liveSlot, memory_order_acquire);
    const SBClickParams *p = &st->slots[slot];

    // --- Adopt new parameters, rebasing so the pending tick does not move ---
    if (p->generation != st->lastParamsGeneration) {
        if (st->framesPerTick > 1.0) {
            double pending = (double)st->epochFrame
                           + (double)st->tickIndexInEpoch * st->framesPerTick;
            if (pending < (double)st->framesElapsed) pending = (double)st->framesElapsed;
            st->epochFrame = (uint64_t)pending;
            st->tickIndexInEpoch = 0;
        }
        st->framesPerTick = p->framesPerTick;
        st->ticksPerBar = p->ticksPerBar;
        st->lastParamsGeneration = p->generation;
    }

    // --- Start: reset phase so tick 0 lands at offset 0 of THIS buffer ---
    if (token != st->lastSeenRunToken) {
        st->lastSeenRunToken = token;
        st->epochFrame = st->framesElapsed;
        st->tickIndexInEpoch = 0;
        st->absoluteTickIndex = 0;
    }

    // --- Voices still ringing from previous buffers ---
    for (int i = 0; i < SB_MAX_VOICES; i++) {
        sb_mix_voice(st, &st->voices[i], 0, frameCount);
    }

    // --- Sound-picker audition, independent of the transport ---
    const int32_t preview = atomic_load_explicit(&st->previewLevel, memory_order_acquire);
    if (preview >= 0 && preview < SB_ACCENT_LEVELS) {
        atomic_store_explicit(&st->previewLevel, -1, memory_order_release);
        SBVoice *v = sb_trigger(st, &p->sounds[preview], p->levelGain[preview]);
        if (v) sb_mix_voice(st, v, 0, frameCount);
    }

    // --- Schedule ticks falling inside [framesElapsed, framesElapsed+frameCount) ---
    if (running && st->framesPerTick > 1.0 && st->ticksPerBar > 0) {
        const double bufferEnd = (double)(st->framesElapsed + frameCount);
        uint32_t fired = 0;

        for (;;) {
            // Recomputed from the epoch every time — NEVER accumulated. This is
            // what bounds drift to double rounding instead of one error per beat.
            const double nextTickFrame = (double)st->epochFrame
                                       + (double)st->tickIndexInEpoch * st->framesPerTick;
            if (nextTickFrame >= bufferEnd) break;

            if (fired >= SB_MAX_TICKS_PER_RENDER) {
                // Pathological catch-up (a stall, or an absurd tempo). Resync to
                // the current buffer rather than machine-gunning the output.
                st->epochFrame = st->framesElapsed + frameCount;
                st->tickIndexInEpoch = 0;
                atomic_fetch_add_explicit(&st->underrunCount, 1, memory_order_relaxed);
                break;
            }

            double rel = nextTickFrame - (double)st->framesElapsed;
            if (rel < 0.0) rel = 0.0;
            uint32_t offset = (uint32_t)rel;
            if (offset >= frameCount) offset = frameCount - 1;

            const uint32_t tickInBar = (uint32_t)(st->absoluteTickIndex % st->ticksPerBar);
            uint8_t level = p->pattern[tickInBar];
            float busGain = (level < SB_ACCENT_LEVELS) ? p->levelGain[level] : 0.0f;

            // Muting the accent bus must not punch a gap in the pulse: an
            // accented tick drops back to whatever it is underneath, so 4/4
            // with no accent is four even quarter notes.
            if (busGain <= 0.0f &&
                (level == SB_LEVEL_DOWNBEAT || level == SB_LEVEL_ACCENT)) {
                level = sb_natural_level(tickInBar, p->ticksPerBeat);
                busGain = p->levelGain[level];
            }

            if (level != SB_LEVEL_SILENT && level < SB_ACCENT_LEVELS) {
                SBVoice *v = sb_trigger(st, &p->sounds[level], busGain);
                if (v) sb_mix_voice(st, v, offset, frameCount);
            }

            // Telemetry for the beat indicator. Stores only — the render thread
            // never signals, dispatches, or touches a semaphore.
            uint64_t hostTime = 0;
            if (ts && (ts->mFlags & kAudioTimeStampHostTimeValid)) {
                hostTime = ts->mHostTime
                         + (uint64_t)((double)offset / st->sampleRate * st->hostTicksPerSecond);
            } else {
                hostTime = mach_absolute_time();
            }
            atomic_store_explicit(&st->lastTickInBar, tickInBar, memory_order_relaxed);
            atomic_store_explicit(&st->lastTickLevel, level, memory_order_relaxed);
            atomic_store_explicit(&st->lastTickHostTime, hostTime, memory_order_relaxed);
            atomic_store_explicit(&st->lastTickIndex, st->absoluteTickIndex + 1, memory_order_release);

            st->tickIndexInEpoch++;
            st->absoluteTickIndex++;
            fired++;
        }
    }

    st->wasRunning = running;

    // --- Master gain ---
    const float gain = sb_bits_float(atomic_load_explicit(&st->masterGainBits, memory_order_acquire));
    if (gain != 1.0f) {
        for (uint32_t i = 0; i < frameCount; i++) st->scratch[i] *= gain;
    }

    // --- Write out. Deinterleaved (one buffer per channel) or interleaved. ---
    if (abl->mNumberBuffers > 1) {
        for (UInt32 b = 0; b < abl->mNumberBuffers; b++) {
            float *out = (float *)abl->mBuffers[b].mData;
            if (!out) continue;
            const uint32_t cap = abl->mBuffers[b].mDataByteSize / sizeof(float);
            const uint32_t n = (cap < frameCount) ? cap : frameCount;
            memcpy(out, st->scratch, (size_t)n * sizeof(float));
            for (uint32_t i = n; i < cap; i++) out[i] = 0.0f;
        }
    } else if (abl->mNumberBuffers == 1) {
        float *out = (float *)abl->mBuffers[0].mData;
        if (out) {
            const UInt32 ch = (abl->mBuffers[0].mNumberChannels > 0)
                            ? abl->mBuffers[0].mNumberChannels : 1;
            const uint32_t cap = abl->mBuffers[0].mDataByteSize / sizeof(float);
            uint32_t idx = 0;
            for (uint32_t f = 0; f < frameCount && idx < cap; f++) {
                const float s = st->scratch[f];
                for (UInt32 c = 0; c < ch && idx < cap; c++) out[idx++] = s;
            }
            for (; idx < cap; idx++) out[idx] = 0.0f;
        }
    }

    st->framesElapsed += frameCount;

    // --- Render-time watchdog (cheap; catches RT-safety regressions) ---
    const uint64_t elapsed = clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - t0;
    uint64_t prevMax = atomic_load_explicit(&st->maxRenderNanos, memory_order_relaxed);
    if (elapsed > prevMax) {
        atomic_store_explicit(&st->maxRenderNanos, elapsed, memory_order_relaxed);
    }
    atomic_fetch_add_explicit(&st->renderCycles, 1, memory_order_relaxed);

    return noErr;
}

// MARK: - Telemetry

SBTickInfo sb_last_tick(const SBEngineState *st) {
    SBTickInfo info = { 0, 0, 0, 0 };
    if (!st) return info;
    info.tickIndex = atomic_load_explicit(&st->lastTickIndex, memory_order_acquire);
    info.tickInBar = atomic_load_explicit(&st->lastTickInBar, memory_order_relaxed);
    info.level     = atomic_load_explicit(&st->lastTickLevel, memory_order_relaxed);
    info.hostTime  = atomic_load_explicit(&st->lastTickHostTime, memory_order_relaxed);
    return info;
}

uint64_t sb_max_render_nanos(const SBEngineState *st) {
    if (!st) return 0;
    return atomic_load_explicit(&st->maxRenderNanos, memory_order_relaxed);
}

void sb_reset_render_stats(SBEngineState *st) {
    if (!st) return;
    atomic_store_explicit(&st->maxRenderNanos, 0, memory_order_relaxed);
    atomic_store_explicit(&st->renderCycles, 0, memory_order_relaxed);
    atomic_store_explicit(&st->underrunCount, 0, memory_order_relaxed);
}
