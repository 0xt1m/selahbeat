import Foundation
import AudioToolbox
import SelahBeatAudioC

/// Drives `sb_render` directly with synthetic timestamps, so the scheduler can
/// be verified deterministically with no audio hardware, no simulator and no
/// timing flakiness.
final class RenderHarness {
    let state: UnsafeMutablePointer<SBEngineState>
    let sampleRate: Double
    private let impulse: UnsafeMutablePointer<Float>
    private var bufferList: UnsafeMutableAudioBufferListPointer
    private let channelData: UnsafeMutablePointer<Float>
    private let capacity: Int

    /// Frame indices (absolute, since engine start) at which a click sounded.
    private(set) var onsets: [Int] = []
    /// Accent level of each onset, parallel to `onsets`.
    private(set) var onsetLevels: [Int] = []

    init(sampleRate: Double = 48_000, maxFrames: Int = 4096) {
        self.sampleRate = sampleRate
        self.capacity = maxFrames
        self.state = sb_engine_create(sampleRate)

        // A one-sample impulse per accent level, with a distinct amplitude for
        // each so the level that fired can be read straight off the output.
        impulse = .allocate(capacity: Int(SB_ACCENT_LEVELS))
        for level in 0..<Int(SB_ACCENT_LEVELS) {
            impulse[level] = Float(level)
        }

        channelData = .allocate(capacity: maxFrames)
        channelData.initialize(repeating: 0, count: maxFrames)

        bufferList = AudioBufferList.allocate(maximumBuffers: 1)
        bufferList[0] = AudioBuffer(
            mNumberChannels: 1,
            mDataByteSize: UInt32(maxFrames * MemoryLayout<Float>.size),
            mData: UnsafeMutableRawPointer(channelData)
        )
    }

    deinit {
        sb_engine_destroy(state)
        impulse.deallocate()
        channelData.deallocate()
        free(bufferList.unsafeMutablePointer)
    }

    /// Publishes params using unit impulses, so every onset is exactly one
    /// non-zero sample and its frame index is unambiguous.
    func publish(framesPerTick: Double, pattern: [UInt8],
                 ticksPerBeat: Int = 1, levelGains: [Float]? = nil) {
        var sounds: [SBSoundRef] = []
        for level in 0..<Int(SB_ACCENT_LEVELS) {
            sounds.append(SBSoundRef(
                samples: level == 0 ? nil : impulse.advanced(by: level),
                length: level == 0 ? 0 : 1,
                gain: 1.0
            ))
        }
        var gains = levelGains ?? [Float](repeating: 1.0, count: Int(SB_ACCENT_LEVELS))
        pattern.withUnsafeBufferPointer { patternPtr in
            sounds.withUnsafeMutableBufferPointer { soundsPtr in
                gains.withUnsafeMutableBufferPointer { gainsPtr in
                    sb_publish_params(
                        state,
                        framesPerTick,
                        UInt32(pattern.count),
                        UInt32(ticksPerBeat),
                        patternPtr.baseAddress,
                        soundsPtr.baseAddress,
                        gainsPtr.baseAddress
                    )
                }
            }
        }
    }

    func start() { sb_start(state) }
    func stop() { sb_stop(state) }

    private var framesRendered = 0

    /// Renders one buffer and records any onsets it contains.
    func render(frames: Int) {
        precondition(frames <= capacity)

        channelData.update(repeating: 0, count: frames)
        bufferList[0].mDataByteSize = UInt32(frames * MemoryLayout<Float>.size)

        var ts = AudioTimeStamp()
        ts.mSampleTime = Float64(framesRendered)
        ts.mHostTime = UInt64(framesRendered)
        ts.mFlags = [.sampleTimeValid]

        let status = sb_render(state, &ts, UInt32(frames), bufferList.unsafeMutablePointer)
        precondition(status == noErr)

        for i in 0..<frames where channelData[i] != 0 {
            onsets.append(framesRendered + i)
            onsetLevels.append(Int(channelData[i].rounded()))
        }
        framesRendered += frames
    }

    func renderFrames(_ total: Int, bufferSize: Int) {
        var remaining = total
        while remaining > 0 {
            let n = Swift.min(bufferSize, remaining)
            render(frames: n)
            remaining -= n
        }
    }

    var totalFramesRendered: Int { framesRendered }

    func resetOnsets() {
        onsets.removeAll()
        onsetLevels.removeAll()
    }
}
