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
#define SB_PAD_VOICES          12   // chord tones plus their detuned partners
#define SB_MAX_CHANNELS        32   // an 18i20 has 20; 32 is headroom, not ambition

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

// MARK: - Pad

/// A sustained chord under the click, in the key of the song.
///
/// Synthesised rather than sampled: a wavetable and a dozen phase accumulators
/// cost almost nothing, never loop, need no audio files, and can be retuned to
/// any key instantly. `table` points into the same arena as the click sounds.
typedef struct {
    const float *table;
    uint32_t     tableLength;
    float        freq[SB_PAD_VOICES];   // Hz
    float        gain[SB_PAD_VOICES];
    uint32_t     voiceCount;
    /// Overall pad level, 0...2. Deliberately independent of the click's
    /// master gain: turning the click down must not take the pad with it.
    float        level;
    /// One-pole lowpass coefficient, 0...1. Part of what makes one pad voice
    /// sound different from another: breathy voices are filtered hard, bright
    /// ones barely at all.
    float        filterCoefficient;
    uint64_t     generation;
} SBPadParams;

/// One bank of running pad oscillators.
///
/// Two of these exist so a key change crossfades rather than jumps: the new
/// chord fades in while the old fades out, which is what a pad player does by
/// hand and what sampled-pad apps do with two decks.
typedef struct {
    /// Each bank keeps the waveform it started with, so changing pad voice
    /// crossfades the timbre rather than swapping it under both banks at once.
    const float *table;
    uint32_t tableLength;
    float    phase[SB_PAD_VOICES];      // 0...1
    float    inc[SB_PAD_VOICES];
    float    gain[SB_PAD_VOICES];
    float    lfoPhase[SB_PAD_VOICES];
    float    lfoInc[SB_PAD_VOICES];
    uint32_t voiceCount;
    float    fade;                      // current 0...1
    float    fadeTarget;
} SBPadSet;

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
    /// Which output channels each source is written to, one bit per channel.
    /// Defaults to every channel, which is what a laptop speaker wants; an
    /// interface lets the click and the pad go to different outputs.
    _Atomic uint32_t clickChannelMask;
    _Atomic uint32_t padChannelMask;

    // --- 3-slot lock-free parameter publish ---
    SBClickParams    slots[SB_PARAM_SLOTS];
    _Atomic int32_t  liveSlot;
    int32_t          writerNextSlot;   // control thread only
    int32_t          writerPrevSlot;   // control thread only
    uint64_t         writerGeneration; // control thread only

    // --- 3-slot publish for the pad, same discipline ---
    SBPadParams      padSlots[SB_PARAM_SLOTS];
    _Atomic int32_t  padLiveSlot;
    int32_t          padWriterNextSlot;
    int32_t          padWriterPrevSlot;
    uint64_t         padWriterGeneration;

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
    float   *scratch;                  // SB_MAX_RENDER_FRAMES floats, click
    float   *padScratch;               // SB_MAX_RENDER_FRAMES floats, pad
    SBPadSet padSets[2];
    int32_t  padCurrentSet;
    uint64_t lastPadGeneration;
    float    padFilterState;           // one-pole lowpass, takes the edge off
    float    padLevelCurrent;          // smoothed, so the slider cannot zipper

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

/// Publish a pad chord. Single-producer, same as sb_publish_params.
///
/// Passing `voiceCount` 0 or `level` 0 silences the pad; it fades rather than
/// stopping dead, so switching it off mid-song is not a click.
void sb_publish_pad(SBEngineState *st,
                    const float *table,
                    uint32_t tableLength,
                    const float *freq,
                    const float *gain,
                    uint32_t voiceCount,
                    float level,
                    float filterCoefficient);

/// Which output channels each source is written to, one bit per channel.
/// Bit 0 is the first output. Zero means "every channel", so a caller that
/// never touches routing keeps the old behaviour.
void sb_set_channel_masks(SBEngineState *st, uint32_t clickMask, uint32_t padMask);

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

/// The pad voices, as harmonic recipes rather than samples.
typedef enum {
    SB_PAD_WARM    = 0,   // soft, reedy - the default
    SB_PAD_STRINGS = 1,   // bowed, more harmonics, more movement
    SB_PAD_GLASS   = 2,   // clean octaves, bell-like on top
    SB_PAD_AIR     = 3,   // nearly a sine; sits furthest under a band
    SB_PAD_ORGAN   = 4,   // drawbar octaves, steady and present
} SBPadVoice;

#define SB_PAD_VOICE_COUNT 5

/// One cycle of a pad waveform, written into the arena.
///
/// A single band-limited cycle is all the pad needs: pitch comes from how fast
/// the oscillators read it, so one table per voice serves every key at no
/// extra cost.
SBSoundRef sb_synth_pad_table(SBArena *arena, uint32_t length, SBPadVoice voice);

#ifdef __cplusplus
}
#endif

#endif /* SB_AUDIO_H */
