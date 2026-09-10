import Testing
import Foundation
@testable import SelahBeatCore
import SelahBeatAudioC

@Suite("Render scheduling")
struct RenderSchedulingTests {

    @Test("First click lands at frame 0 of the very next buffer")
    func startIsImmediate() {
        let h = RenderHarness()
        h.publish(framesPerTick: 24_000, pattern: [1, 3, 3, 3])

        // Render a while with the transport stopped: nothing should sound.
        h.renderFrames(4096, bufferSize: 256)
        #expect(h.onsets.isEmpty)

        let framesBeforeStart = h.totalFramesRendered
        h.start()
        h.render(frames: 256)

        // The whole product requirement: the downbeat is the first sample of
        // the first buffer after Start, not one buffer later.
        #expect(h.onsets.first == framesBeforeStart)
    }

    @Test("Ticks are sample-accurate and do not drift over 10 minutes")
    func noDriftOverTenMinutes() {
        let h = RenderHarness()
        let sampleRate = 48_000.0
        let bpm = 120.0
        let framesPerTick = sampleRate * 60.0 / bpm   // exactly 24000

        h.publish(framesPerTick: framesPerTick, pattern: [1, 3, 3, 3])
        h.start()
        h.render(frames: 1024)
        let epoch = h.onsets[0]

        h.renderFrames(Int(sampleRate * 600), bufferSize: 1024)

        #expect(h.onsets.count > 1_000)
        for (i, onset) in h.onsets.enumerated() {
            let expected = epoch + Int((Double(i) * framesPerTick).rounded(.down))
            // Sample-accurate: the scheduler recomputes from the epoch every
            // tick instead of accumulating, so error cannot grow with time.
            #expect(abs(onset - expected) <= 1, "tick \(i) landed at \(onset), expected \(expected)")
        }
    }

    @Test("Fractional frames-per-tick still lands within one sample")
    func oddTempoIsAccurate() {
        let h = RenderHarness()
        let sampleRate = 48_000.0
        let bpm = 143.7
        // 7/8 grouped 2+2+3, eighth-note ticks
        let pattern: [UInt8] = [1, 4, 3, 4, 3, 4, 4]
        let framesPerTick = sampleRate * 60.0 / (bpm * 1.0)

        h.publish(framesPerTick: framesPerTick, pattern: pattern)
        h.start()
        h.render(frames: 512)
        let epoch = h.onsets[0]

        h.renderFrames(Int(sampleRate * 120), bufferSize: 512)

        for (i, onset) in h.onsets.enumerated() {
            let expected = epoch + Int(Double(i) * framesPerTick)
            #expect(abs(onset - expected) <= 1, "tick \(i) at \(onset), expected ~\(expected)")
        }
    }

    @Test("Onsets land mid-buffer, not quantised to buffer boundaries")
    func onsetsAreSubBuffer() {
        let h = RenderHarness()
        // 100 frames per tick against 256-frame buffers guarantees ticks fall
        // at many different offsets within a buffer.
        h.publish(framesPerTick: 100.0, pattern: [1, 3, 3, 3])
        h.start()
        h.renderFrames(256 * 40, bufferSize: 256)

        let offsets = Set(h.onsets.map { $0 % 256 })
        #expect(offsets.count > 5, "onsets appear quantised to buffer boundaries: \(offsets)")
    }

    @Test("A tempo change does not move the already-scheduled next tick")
    func tempoChangeRebasesWithoutStutter() {
        let h = RenderHarness()
        let slow = 24_000.0   // 120 BPM
        let fast = 12_000.0   // 240 BPM

        h.publish(framesPerTick: slow, pattern: [1, 3, 3, 3])
        h.start()
        h.render(frames: 1024)
        let epoch = h.onsets[0]

        // Advance to just past the second tick, then change tempo mid-interval.
        h.renderFrames(30_000, bufferSize: 1024)
        let onsetsBefore = h.onsets.count
        h.publish(framesPerTick: fast, pattern: [1, 3, 3, 3])
        h.renderFrames(30_000, bufferSize: 1024)

        // The tick that was already pending must stay exactly where it was
        // going to land — otherwise dragging a BPM slider stutters or double-hits.
        let pending = epoch + Int(Double(onsetsBefore) * slow)
        #expect(h.onsets.count > onsetsBefore)
        #expect(abs(h.onsets[onsetsBefore] - pending) <= 1,
                "pending tick moved from \(pending) to \(h.onsets[onsetsBefore])")

        // And subsequent ticks follow the new tempo.
        if h.onsets.count > onsetsBefore + 2 {
            let gap = h.onsets[onsetsBefore + 2] - h.onsets[onsetsBefore + 1]
            #expect(abs(Double(gap) - fast) <= 1)
        }
    }

    @Test("Restarting resets the bar so a mid-song restart begins on the downbeat")
    func restartBeginsOnDownbeat() {
        let h = RenderHarness()
        h.publish(framesPerTick: 24_000, pattern: [1, 3, 3, 3])
        h.start()
        h.renderFrames(24_000 * 6 + 500, bufferSize: 256)   // stop mid-bar
        h.stop()
        h.renderFrames(5_000, bufferSize: 256)

        h.resetOnsets()
        h.start()
        h.render(frames: 256)

        // Level 1 is the downbeat. Stopping and restarting mid-song must not
        // resume on beat 3.
        #expect(h.onsetLevels.first == Int(SB_LEVEL_DOWNBEAT.rawValue))
    }

    @Test("Silent ticks produce no sound")
    func mutedTicksAreSilent() {
        let h = RenderHarness()
        h.publish(framesPerTick: 1_000, pattern: [1, 0, 0, 0])
        h.start()
        h.renderFrames(1_000 * 8, bufferSize: 256)

        #expect(h.onsets.count == 2)
        #expect(h.onsetLevels.allSatisfy { $0 == Int(SB_LEVEL_DOWNBEAT.rawValue) })
    }

    @Test("Stopped transport renders exact silence")
    func stoppedIsSilent() {
        let h = RenderHarness()
        h.publish(framesPerTick: 24_000, pattern: [1, 3, 3, 3])
        h.renderFrames(48_000, bufferSize: 512)
        #expect(h.onsets.isEmpty)
    }
}
