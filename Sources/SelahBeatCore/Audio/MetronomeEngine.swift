import Foundation
import AVFoundation
import OSLog
import SelahBeatAudioC

#if os(macOS)
import CoreAudio
#endif

/// Snapshot of what the audio hardware is actually doing, for the diagnostics
/// panel. A drummer debugging Bluetooth lag needs to see these numbers.
public struct AudioDiagnostics: Sendable, Equatable {
    public var sampleRate: Double = 0
    public var bufferFrames: Int = 0
    public var outputLatency: TimeInterval = 0
    public var route: String = ""
    public var isLowLatencyRoute: Bool = true
    public var engineRunning: Bool = false
    public var maxRenderMicros: Double = 0
    /// Fraction of the buffer period spent in the render callback. Anything
    /// approaching 1.0 means dropouts.
    public var renderLoad: Double = 0

    public var startLatencyEstimate: TimeInterval {
        guard sampleRate > 0 else { return 0 }
        return Double(bufferFrames) / sampleRate + outputLatency
    }
}

/// Owns the audio graph and the C engine state.
///
/// The graph is started once at launch and NEVER stopped. It renders silence
/// when idle and never reports `isSilence`, which keeps CoreAudio from powering
/// the IO chain down. Start is therefore two atomic stores, and the first click
/// sounds on the very next hardware callback rather than after an
/// `AVAudioEngine.start()` that can cost 5-80 ms.
public final class MetronomeEngine: @unchecked Sendable {
    // All mutable state is either confined to the main actor or lives behind
    // C atomics inside `state`. This class holds no unsynchronised Swift state.
    private let state: UnsafeMutablePointer<SBEngineState>
    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private var bank: ClickBank?
    private let session: AudioSessionConfiguring
    private let log = Logger(subsystem: "app.selahbeat", category: "audio")

    private var currentSampleRate: Double = 48_000
    private var preferredBufferFrames: Int = 256

    // Last published configuration, so any single change can republish the set.
    private var bpm: Double = 120
    private var pattern: ClickPattern = .standard(for: .fourFour, subdivision: .quarter)
    private var timbre: ClickTimbre = .woodblock

    public private(set) var lastError: String?

    public init(session: AudioSessionConfiguring) {
        self.session = session
        self.state = sb_engine_create(48_000)
    }

    deinit {
        engine.stop()
        sb_engine_destroy(state)
    }

    // MARK: - Lifecycle

    /// Builds and starts the graph. Call once, as early as possible in launch.
    public func startEngine() {
        do {
            try session.activate(preferredBufferFrames: preferredBufferFrames)
        } catch {
            log.error("Audio session activation failed: \(error.localizedDescription)")
        }

        #if os(macOS)
        applyPreferredBufferFrames()
        #endif

        buildGraph()
        startGraph()
    }

    private func buildGraph() {
        // Deliberately never touch engine.mainMixerNode - merely referencing it
        // instantiates a mixer and a possible format conversion between us and
        // the output.
        let hardwareFormat = engine.outputNode.outputFormat(forBus: 0)
        let sampleRate = hardwareFormat.sampleRate > 0 ? hardwareFormat.sampleRate : 48_000
        let channels = max(1, min(hardwareFormat.channelCount, 2))

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels) else {
            lastError = "Could not create audio format"
            return
        }

        currentSampleRate = sampleRate
        sb_engine_set_sample_rate(state, sampleRate)
        rebuildBank(sampleRate: sampleRate)

        let statePointer = state
        let node = AVAudioSourceNode(format: format) { isSilence, timestamp, frameCount, audioBufferList in
            // Never claim silence: if the IO chain powers down between songs,
            // the next Start pays the wake-up cost and the whole design fails.
            isSilence.pointee = false
            return sb_render(statePointer, timestamp, frameCount, audioBufferList)
        }

        sourceNode = node
        engine.attach(node)
        engine.connect(node, to: engine.outputNode, format: format)
        publishParams()
    }

    private func startGraph() {
        guard !engine.isRunning else { return }
        do {
            engine.prepare()
            try engine.start()
            lastError = nil
            log.info("Audio graph running at \(self.currentSampleRate, privacy: .public) Hz")
        } catch {
            lastError = error.localizedDescription
            log.error("Engine start failed: \(error.localizedDescription)")
        }
    }

    private func rebuildBank(sampleRate: Double) {
        guard bank?.sampleRate != sampleRate else { return }
        bank = ClickBank(sampleRate: sampleRate)
        if bank == nil {
            lastError = "Could not synthesise click sounds"
        }
    }

    /// Rebuilds the graph after a device or route change. Without this the
    /// click silently dies mid-service when someone plugs in headphones.
    public func handleConfigurationChange() {
        let wasRunning = sb_is_running(state)
        sb_stop(state)

        if let node = sourceNode {
            engine.disconnectNodeOutput(node)
            engine.detach(node)
            sourceNode = nil
        }
        engine.stop()

        buildGraph()
        startGraph()

        if wasRunning {
            // Phase restarts at the downbeat. There is no meaningful way to
            // preserve phase across a device swap, and a fresh downbeat is what
            // a drummer would want anyway.
            sb_start(state)
        }
    }

    #if os(macOS)
    private func applyPreferredBufferFrames() {
        guard let audioUnit = engine.outputNode.audioUnit else { return }
        var frames = UInt32(preferredBufferFrames)
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioDevicePropertyBufferFrameSize,
            kAudioUnitScope_Global,
            0,
            &frames,
            UInt32(MemoryLayout<UInt32>.size)
        )
        if status != noErr {
            log.notice("Could not set buffer frame size (status \(status)); using device default")
        }
    }

    private func actualBufferFrames() -> Int {
        guard let audioUnit = engine.outputNode.audioUnit else { return preferredBufferFrames }
        var frames: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioUnitGetProperty(
            audioUnit,
            kAudioDevicePropertyBufferFrameSize,
            kAudioUnitScope_Global,
            0,
            &frames,
            &size
        )
        return status == noErr && frames > 0 ? Int(frames) : preferredBufferFrames
    }
    #endif

    // MARK: - Transport

    /// Two atomic stores. Nothing else happens here by design.
    public func start() { sb_start(state) }
    public func stop() { sb_stop(state) }
    public var isRunning: Bool { sb_is_running(state) }

    public func toggle() {
        if isRunning { stop() } else { start() }
    }

    // MARK: - Parameters

    public func setTempo(_ newBPM: Double) {
        bpm = Song.clampBPM(newBPM)
        publishParams()
    }

    public func setPattern(_ newPattern: ClickPattern) {
        pattern = newPattern
        publishParams()
    }

    public func setTimbre(_ newTimbre: ClickTimbre) {
        timbre = newTimbre
        publishParams()
    }

    public func setMasterGain(_ gain: Float) {
        sb_set_master_gain(state, gain)
    }

    /// Auditions a sound without starting the transport.
    public func preview(_ newTimbre: ClickTimbre) {
        timbre = newTimbre
        publishParams()
        sb_preview(state, Int32(SB_LEVEL_DOWNBEAT.rawValue))
    }

    private func publishParams() {
        guard let bank else { return }
        var sounds = bank.sounds(for: timbre)
        var levels = pattern.levels
        let framesPerTick = pattern.framesPerTick(bpm: bpm, sampleRate: currentSampleRate)

        levels.withUnsafeBufferPointer { levelsPtr in
            sounds.withUnsafeMutableBufferPointer { soundsPtr in
                sb_publish_params(
                    state,
                    framesPerTick,
                    UInt32(levels.count),
                    levelsPtr.baseAddress,
                    soundsPtr.baseAddress
                )
            }
        }
    }

    // MARK: - Telemetry

    public func lastTick() -> SBTickInfo { sb_last_tick(state) }

    public var outputLatency: TimeInterval { session.outputLatency }

    public func diagnostics() -> AudioDiagnostics {
        var d = AudioDiagnostics()
        d.sampleRate = currentSampleRate
        #if os(macOS)
        d.bufferFrames = actualBufferFrames()
        d.route = session.routeDescription
        d.isLowLatencyRoute = session.isLowLatencyRoute
        #else
        d.bufferFrames = Int((AVAudioSession.sharedInstance().ioBufferDuration * currentSampleRate).rounded())
        d.route = session.routeDescription
        d.isLowLatencyRoute = session.isLowLatencyRoute
        #endif
        d.outputLatency = session.outputLatency
        d.engineRunning = engine.isRunning
        let nanos = Double(sb_max_render_nanos(state))
        d.maxRenderMicros = nanos / 1000.0
        if currentSampleRate > 0, d.bufferFrames > 0 {
            let periodNanos = Double(d.bufferFrames) / currentSampleRate * 1e9
            d.renderLoad = periodNanos > 0 ? nanos / periodNanos : 0
        }
        return d
    }

    public func resetRenderStats() { sb_reset_render_stats(state) }
}
