//
//  SBSynth.c — procedural click synthesis. CONTROL THREAD ONLY.
//
//  Clicks are generated at launch (and on any sample-rate change) rather than
//  shipped as audio files. That keeps the app tiny, removes decode and format
//  conversion entirely, and renders every sound at the hardware's exact rate
//  so there is never a resampling step.
//

#include "include/SBAudio.h"

#include <stdlib.h>
#include <string.h>
#include <math.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

// MARK: - Arena

struct SBArena {
    float *base;
    size_t capacity;   // in floats
    size_t used;
};

SBArena *sb_arena_create(size_t floatCapacity) {
    if (floatCapacity == 0) return NULL;
    SBArena *a = (SBArena *)calloc(1, sizeof(SBArena));
    if (!a) return NULL;
    a->base = (float *)calloc(floatCapacity, sizeof(float));
    if (!a->base) {
        free(a);
        return NULL;
    }
    a->capacity = floatCapacity;
    a->used = 0;
    return a;
}

void sb_arena_destroy(SBArena *arena) {
    if (!arena) return;
    free(arena->base);
    free(arena);
}

static float *sb_arena_alloc(SBArena *arena, size_t floats) {
    if (!arena || floats == 0) return NULL;
    if (arena->used + floats > arena->capacity) return NULL;
    float *p = arena->base + arena->used;
    arena->used += floats;
    return p;
}

// MARK: - Small DSP helpers

/// xorshift32 — deterministic, so a given timbre sounds identical every launch.
static inline float sb_noise(uint32_t *state) {
    uint32_t x = *state;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    *state = x;
    return (float)((int32_t)x) * (1.0f / 2147483648.0f);
}

typedef struct {
    double b0, b1, b2, a1, a2;
    double z1, z2;
} SBBiquad;

static void sb_biquad_bandpass(SBBiquad *f, double freq, double q, double sampleRate) {
    const double w0 = 2.0 * M_PI * freq / sampleRate;
    const double alpha = sin(w0) / (2.0 * q);
    const double cosw0 = cos(w0);
    const double a0 = 1.0 + alpha;

    f->b0 = alpha / a0;
    f->b1 = 0.0;
    f->b2 = -alpha / a0;
    f->a1 = (-2.0 * cosw0) / a0;
    f->a2 = (1.0 - alpha) / a0;
    f->z1 = f->z2 = 0.0;
}

static void sb_biquad_highpass(SBBiquad *f, double freq, double q, double sampleRate) {
    const double w0 = 2.0 * M_PI * freq / sampleRate;
    const double alpha = sin(w0) / (2.0 * q);
    const double cosw0 = cos(w0);
    const double a0 = 1.0 + alpha;

    f->b0 = ((1.0 + cosw0) / 2.0) / a0;
    f->b1 = (-(1.0 + cosw0)) / a0;
    f->b2 = ((1.0 + cosw0) / 2.0) / a0;
    f->a1 = (-2.0 * cosw0) / a0;
    f->a2 = (1.0 - alpha) / a0;
    f->z1 = f->z2 = 0.0;
}

/// Transposed direct form II.
static inline float sb_biquad_process(SBBiquad *f, float in) {
    const double x = (double)in;
    const double y = f->b0 * x + f->z1;
    f->z1 = f->b1 * x - f->a1 * y + f->z2;
    f->z2 = f->b2 * x - f->a2 * y;
    return (float)y;
}

/// Raised-cosine attack ramp, so no click starts with a discontinuity.
static inline float sb_attack(uint32_t i, uint32_t attackSamples) {
    if (attackSamples == 0 || i >= attackSamples) return 1.0f;
    const double t = (double)i / (double)attackSamples;
    return (float)(0.5 - 0.5 * cos(M_PI * t));
}

static inline float sb_decay(uint32_t i, double tauSamples) {
    return (float)exp(-(double)i / tauSamples);
}

// MARK: - Level shaping

/// Each accent level is the same recipe transposed and rebalanced, which keeps
/// a timbre family coherent: downbeat higher and louder, subdivision quieter
/// and shorter so it sits under the beat rather than competing with it.
static void sb_level_shape(int32_t level, double *pitchMul, double *gain, double *decayMul) {
    switch (level) {
        case SB_LEVEL_DOWNBEAT:  *pitchMul = 1.500; *gain = 1.00; *decayMul = 1.00; break;
        case SB_LEVEL_ACCENT:    *pitchMul = 1.250; *gain = 0.82; *decayMul = 0.90; break;
        case SB_LEVEL_QUARTER:   *pitchMul = 1.000; *gain = 0.68; *decayMul = 0.85; break;
        case SB_LEVEL_EIGHTH:    *pitchMul = 1.000; *gain = 0.38; *decayMul = 0.55; break;
        // Sixteenths sit under the eighths by default: at speed they are
        // texture, not information.
        case SB_LEVEL_SIXTEENTH: *pitchMul = 1.000; *gain = 0.26; *decayMul = 0.40; break;
        default:                 *pitchMul = 1.000; *gain = 0.68; *decayMul = 0.85; break;
    }
}

typedef struct {
    double baseFreq;
    double tauMs;       // exponential decay time constant
    double lengthMs;
    double attackMs;
} SBTimbreSpec;

static SBTimbreSpec sb_timbre_spec(SBTimbre t) {
    switch (t) {
        case SB_TIMBRE_SINE:      return (SBTimbreSpec){  880.0,  25.0,  120.0, 1.0 };
        case SB_TIMBRE_WOODBLOCK: return (SBTimbreSpec){ 1100.0,  12.0,   70.0, 0.3 };
        case SB_TIMBRE_COWBELL:   return (SBTimbreSpec){  587.0,  90.0,  320.0, 0.5 };
        case SB_TIMBRE_STICK:     return (SBTimbreSpec){ 3000.0,   6.0,   40.0, 0.1 };
        case SB_TIMBRE_RIM:       return (SBTimbreSpec){ 2500.0,  40.0,  160.0, 0.2 };
        case SB_TIMBRE_PULSE:     return (SBTimbreSpec){  400.0, 120.0,  400.0, 15.0 };
        default:                  return (SBTimbreSpec){  880.0,  25.0,  120.0, 1.0 };
    }
}

// MARK: - Synthesis

SBSoundRef sb_synth_render(SBArena *arena, SBTimbre timbre, int32_t level, double sampleRate) {
    SBSoundRef out = { NULL, 0, 0.0f };
    if (!arena || sampleRate <= 0.0) return out;
    if (level <= SB_LEVEL_SILENT || level >= SB_ACCENT_LEVELS) return out;
    if (timbre < 0 || timbre >= SB_TIMBRE_COUNT) timbre = SB_TIMBRE_SINE;

    double pitchMul, levelGain, decayMul;
    sb_level_shape(level, &pitchMul, &levelGain, &decayMul);

    const SBTimbreSpec spec = sb_timbre_spec(timbre);
    const double freq = spec.baseFreq * pitchMul;
    const double tau = (spec.tauMs * decayMul) * 0.001 * sampleRate;
    const uint32_t n = (uint32_t)(spec.lengthMs * decayMul * 0.001 * sampleRate);
    const uint32_t attack = (uint32_t)(spec.attackMs * 0.001 * sampleRate);

    if (n == 0) return out;

    float *buf = sb_arena_alloc(arena, n);
    if (!buf) return out;

    // Seed varies per timbre/level so noise-based sounds differ, but is fixed
    // across launches.
    uint32_t rng = 0x9E3779B9u ^ ((uint32_t)timbre * 2654435761u) ^ ((uint32_t)level * 40503u);

    const double sr = sampleRate;
    SBBiquad filt;

    switch (timbre) {
        case SB_TIMBRE_SINE: {
            for (uint32_t i = 0; i < n; i++) {
                const double t = (double)i / sr;
                buf[i] = (float)(sin(2.0 * M_PI * freq * t)) * sb_decay(i, tau) * sb_attack(i, attack);
            }
            break;
        }

        case SB_TIMBRE_WOODBLOCK: {
            // Two inharmonic partials plus a very short noise transient: reads
            // as a block/rimshot rather than a beep.
            const double f2 = freq * 2.76;
            const uint32_t transient = (uint32_t)(0.002 * sr);
            for (uint32_t i = 0; i < n; i++) {
                const double t = (double)i / sr;
                double s = 0.75 * sin(2.0 * M_PI * freq * t)
                         + 0.35 * sin(2.0 * M_PI * f2 * t);
                if (i < transient) {
                    s += 0.6 * sb_noise(&rng) * (1.0 - (double)i / (double)transient);
                }
                buf[i] = (float)s * sb_decay(i, tau) * sb_attack(i, attack);
            }
            break;
        }

        case SB_TIMBRE_COWBELL: {
            const double f1 = freq;
            const double f2 = freq * 1.4396;   // the classic 587/845 ratio
            sb_biquad_bandpass(&filt, freq * 1.2, 1.4, sr);
            for (uint32_t i = 0; i < n; i++) {
                const double t = (double)i / sr;
                const double sq1 = (sin(2.0 * M_PI * f1 * t) >= 0.0) ? 1.0 : -1.0;
                const double sq2 = (sin(2.0 * M_PI * f2 * t) >= 0.0) ? 1.0 : -1.0;
                float s = (float)(0.5 * sq1 + 0.5 * sq2);
                s = sb_biquad_process(&filt, s);
                buf[i] = s * sb_decay(i, tau) * sb_attack(i, attack);
            }
            break;
        }

        case SB_TIMBRE_STICK: {
            // Short filtered noise burst — cuts through a loud stage better
            // than any pitched sound.
            sb_biquad_highpass(&filt, freq, 0.707, sr);
            const uint32_t burst = (uint32_t)(0.003 * sr);
            for (uint32_t i = 0; i < n; i++) {
                float s = (i < burst) ? sb_noise(&rng) : 0.0f;
                s = sb_biquad_process(&filt, s);
                buf[i] = s * sb_decay(i, tau) * sb_attack(i, attack);
            }
            break;
        }

        case SB_TIMBRE_RIM: {
            // Noise into a high-Q bandpass — a ringing "tick".
            sb_biquad_bandpass(&filt, freq, 12.0, sr);
            const uint32_t burst = (uint32_t)(0.004 * sr);
            for (uint32_t i = 0; i < n; i++) {
                float s = (i < burst) ? sb_noise(&rng) : 0.0f;
                s = sb_biquad_process(&filt, s);
                buf[i] = s * sb_decay(i, tau) * sb_attack(i, attack);
            }
            break;
        }

        case SB_TIMBRE_PULSE: {
            // Slow attack, low fundamental — for in-ears, where a hard
            // transient every beat is fatiguing across a 90-minute service.
            for (uint32_t i = 0; i < n; i++) {
                const double t = (double)i / sr;
                double s = sin(2.0 * M_PI * freq * t)
                         + 0.2 * sin(2.0 * M_PI * freq * 2.0 * t);
                buf[i] = (float)s * sb_decay(i, tau) * sb_attack(i, attack);
            }
            break;
        }

        default:
            break;
    }

    // Normalise to unit peak, then apply the level's gain, so every timbre is
    // perceptually balanced against the others and the master gain means the
    // same thing regardless of which sound is selected.
    float peak = 0.0f;
    for (uint32_t i = 0; i < n; i++) {
        const float a = fabsf(buf[i]);
        if (a > peak) peak = a;
    }
    if (peak > 1e-6f) {
        const float norm = 1.0f / peak;
        for (uint32_t i = 0; i < n; i++) buf[i] *= norm;
    }

    // Short fade-out so a truncated tail never pops.
    const uint32_t fade = (n > 64) ? 64 : n;
    for (uint32_t i = 0; i < fade; i++) {
        const float g = (float)i / (float)fade;
        buf[n - 1 - i] *= g;
    }

    out.samples = buf;
    out.length = n;
    out.gain = (float)levelGain;
    return out;
}
