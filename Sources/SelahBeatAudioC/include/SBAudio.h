//
//  SBAudio.h — SelahBeat real-time audio core.
//
//  Everything in this module runs, or feeds, the audio render thread.
//
//  THE RULE: sb_render() and everything it calls must never allocate, never
//  take a lock, never call into Objective-C or the Swift runtime, and never
//  block. Breaking this rule produces audible dropouts that only appear under
//  load, so it is enforced structurally: the Swift render block does nothing
//  but call sb_render().
//

#ifndef SB_AUDIO_H
#define SB_AUDIO_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdatomic.h>
#include <CoreAudioTypes/CoreAudioTypes.h>

#ifdef __cplusplus
extern "C" {
#endif

// MARK: - Limits

#define SB_MAX_TICKS_PER_BAR   64
#define SB_ACCENT_LEVELS        6   // see SBAccentLevel
#define SB_PARAM_SLOTS          3
#define SB_MAX_VOICES           8
#define SB_MAX_RENDER_FRAMES 8192   // scratch buffer size; larger buffers are refused
#define SB_MAX_TICKS_PER_RENDER 32  // burst guard, see SBRender.c

/// Which sound a tick plays, and which mix bus it is scaled by.
///
/// Eighths and sixteenths are separate levels rather than one "subdivision"
/// so each can have its own volume: a drummer usually wants sixteenths well
/// under the eighths, and both under the beat.
typedef enum {
    SB_LEVEL_SILENT    = 0,   // muted tick
    SB_LEVEL_DOWNBEAT  = 1,
    SB_LEVEL_ACCENT    = 2,
    SB_LEVEL_QUARTER   = 3,
    SB_LEVEL_EIGHTH    = 4,
    SB_LEVEL_SIXTEENTH = 5,
} SBAccentLevel;

// MARK: - Sounds

/// A pre-rendered click. `samples` points into an arena owned by the control
/// thread and is guaranteed to outlive any render that can observe it.
typedef struct {
    const float *samples;
    uint32_t     length;
    float        gain;
} SBSoundRef;

// MARK: - Parameters

/// The compound parameter block. Published as a unit so the render thread can
/// never observe a new `ticksPerBar` alongside an old `pattern`.
typedef struct {
    double     framesPerTick;
    uint32_t   ticksPerBar;
    /// Ticks per counted beat. The render loop needs it to work out what a
    /// tick *naturally* is, so an accented tick can fall back to its own
    /// layer when the accent bus is muted.
    uint32_t   ticksPerBeat;
    uint8_t    pattern[SB_MAX_TICKS_PER_BAR];   // SBAccentLevel per tick
    SBSoundRef sounds[SB_ACCENT_LEVELS];
    /// Per-level mix busses, 0...2. Applied on top of each sound's own gain so
    /// the balance can be changed live without re-synthesising anything.
    float      levelGain[SB_ACCENT_LEVELS];
    uint64_t   generation;
} SBClickParams;

// MARK: - Voices

typedef struct {
    const float *samples;
    uint32_t     length;
    uint32_t     cursor;
    float        gain;
    int32_t      active;
    uint64_t     order;      // for oldest-first stealing
} SBVoice;

// MARK: - Engine state

/// All state shared between the control thread and the render thread.
///
/// Ownership is strictly partitioned — see the section comments. The only
/// cross-thread communication is via C11 atomics and the 3-slot publish buffer.
typedef struct {
    // --- Control thread writes, render thread reads (atomics) ---
    _Atomic int32_t  running;
    _Atomic uint64_t runToken;         // bumped on every Start; resets phase
    _Atomic uint32_t masterGainBits;   // float bit pattern
    _Atomic int32_t  previewLevel;     // >=0 fires one voice, then resets to -1

    // --- 3-slot lock-free parameter publish ---
    SBClickParams    slots[SB_PARAM_SLOTS];
    _Atomic int32_t  liveSlot;
    int32_t          writerNextSlot;   // control thread only
    int32_t          writerPrevSlot;   // control thread only
    uint64_t         writerGeneration; // control thread only

    // --- Render thread only (never touched by the control thread once running) ---
    double   sampleRate;
    double   hostTicksPerSecond;
    uint64_t framesElapsed;
    uint64_t epochFrame;
    uint64_t tickIndexInEpoch;
    uint64_t absoluteTickIndex;
    uint64_t lastSeenRunToken;
    uint64_t lastParamsGeneration;
    double   framesPerTick;
    uint32_t ticksPerBar;
    int32_t  wasRunning;
    uint64_t voiceOrderCounter;
    SBVoice  voices[SB_MAX_VOICES];
    float   *scratch;                  // SB_MAX_RENDER_FRAMES floats

    // --- Render thread writes, UI polls (never signals, never dispatches) ---
    _Atomic uint64_t lastTickIndex;
    _Atomic uint32_t lastTickInBar;
    _Atomic uint32_t lastTickLevel;
    _Atomic uint64_t lastTickHostTime;
    _Atomic uint64_t renderCycles;
    _Atomic uint64_t maxRenderNanos;
    _Atomic uint64_t underrunCount;
} SBEngineState;

// MARK: - Lifecycle (control thread)

SBEngineState *sb_engine_create(double sampleRate);
void           sb_engine_destroy(SBEngineState *st);

/// Called when the hardware sample rate changes. Resets phase; the caller must
/// re-render the sound bank and re-publish params for the new rate.
void sb_engine_set_sample_rate(SBEngineState *st, double sampleRate);

// MARK: - Transport (control thread)

/// Start. Cheap by design: two atomic stores. The first tick fires at offset 0
/// of the very next render callback.
void sb_start(SBEngineState *st);

/// Stop. In-flight voices ring out naturally — truncating a decaying voice pops.
void sb_stop(SBEngineState *st);

bool sb_is_running(const SBEngineState *st);

void sb_set_master_gain(SBEngineState *st, float gain);

/// Audition one sound without starting the transport (for the sound picker).
void sb_preview(SBEngineState *st, int32_t level);

// MARK: - Parameters (control thread)

/// Publish a new parameter set. Single-producer only: call from one serialized
/// context (the main actor). Takes effect on the next render callback.
void sb_publish_params(SBEngineState *st,
                       double framesPerTick,
                       uint32_t ticksPerBar,
                       uint32_t ticksPerBeat,
                       const uint8_t *pattern,
                       const SBSoundRef *sounds,
                       const float *levelGain);

// MARK: - Render (audio thread — REAL-TIME, see THE RULE above)

/// `ts` may be NULL. Returns noErr, or kAudio_ParamError for a malformed
/// buffer list. Always fills the output (with zeros when idle) and never
/// reports silence, so the IO chain stays powered up between songs.
OSStatus sb_render(SBEngineState *st,
                   const AudioTimeStamp *ts,
                   uint32_t frameCount,
                   AudioBufferList *abl);

// MARK: - Telemetry (any thread)

typedef struct {
    uint64_t tickIndex;
    uint32_t tickInBar;
    uint32_t level;
    uint64_t hostTime;   // mach host time of the tick's first sample
} SBTickInfo;

SBTickInfo sb_last_tick(const SBEngineState *st);
uint64_t   sb_max_render_nanos(const SBEngineState *st);
void       sb_reset_render_stats(SBEngineState *st);

// MARK: - Sound synthesis (control thread — allocates, never call from render)

typedef enum {
    SB_TIMBRE_SINE       = 0,
    SB_TIMBRE_WOODBLOCK  = 1,
    SB_TIMBRE_COWBELL    = 2,
    SB_TIMBRE_STICK      = 3,
    SB_TIMBRE_RIM        = 4,
    SB_TIMBRE_PULSE      = 5,
    SB_TIMBRE_COUNT      = 6,
} SBTimbre;

/// Bump-allocated pool for click sample data. Never freed while an engine can
/// still observe it; a sample-rate change publishes a new arena and frees the
/// old one on a delay.
typedef struct SBArena SBArena;

SBArena *sb_arena_create(size_t floatCapacity);
void     sb_arena_destroy(SBArena *arena);

/// Renders one click into `arena`. `level` selects pitch/gain within the
/// timbre family (downbeat higher and louder, subdivision quieter and duller).
/// Returns a sound with samples == NULL if the arena is exhausted.
SBSoundRef sb_synth_render(SBArena *arena, SBTimbre timbre, int32_t level, double sampleRate);

#ifdef __cplusplus
}
#endif

#endif /* SB_AUDIO_H */
