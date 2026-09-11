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

    /// Banks whose sample memory the render thread may still be reading.
    ///
    /// Releasing a ClickBank frees its arena, and the published parameters hold
    /// raw pointers into it. Dropping the old bank the instant a new one is
    /// built is a use-after-free on the audio thread - which is what made
    /// connecting AirPods crash, since the route change alters the sample rate.
    /// Retired banks are held until the render thread has certainly adopted the
    /// new pointers.
    private var retiredBanks: [ClickBank] = []

    /// A route change can arrive as both a session route-change notification and
    /// an engine configuration-change notification. Rebuilding the graph
    /// re-entrantly corrupts it.
    private var isReconfiguring = false

    // Last published configuration, so any single change can republish the set.
    private var bpm: Double = 120
    private var pattern: ClickPattern = .standard(for: .fourFour, subdivision: .quarter)
    private var timbre: ClickTimbre = .woodblock
    /// Per-level mix busses, indexed by SBAccentLevel.
    private var levelGains = [Float](repeating: 1.0, count: Int(SB_ACCENT_LEVELS))

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
        guard let newBank = ClickBank(sampleRate: sampleRate) else {
            // Keep the existing bank rather than leaving the engine with none.
            lastError = "Could not synthesise click sounds"
            return
        }
        if let previous = bank {
            retiredBanks.append(previous)
        }
        bank = newBank
    }

    /// Frees retired banks once the render thread cannot still be reading them.
    ///
    /// Half a second is far longer than needed - the parameter publish is
    /// picked up within one render quantum (~5 ms) and the longest click tail
    /// is 400 ms - but this runs on a route change, not in any hot path.
    private func releaseRetiredBanks() {
        guard !retiredBanks.isEmpty else { return }
        let doomed = retiredBanks
        retiredBanks.removeAll()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            _ = doomed.count   // holds the references until the deadline
        }
    }

    /// Rebuilds the graph after a device or route change. Without this the
    /// click silently dies mid-service when someone plugs in headphones.
    public func handleConfigurationChange() {
        guard !isReconfiguring else { return }
        isReconfiguring = true
        defer { isReconfiguring = false }

        // The click always stops on a route change. Resuming into a device the
        // drummer just plugged in or pulled out is worse than silence: the
        // latency characteristics have changed and they are not expecting it.
        sb_stop(state)
        engine.stop()

        // Immediately after a route change the output format can briefly report
        // a zero sample rate. Connecting with that raises an Objective-C
        // exception that Swift cannot catch, so bail out; another notification
        // follows once the route has settled.
        let hardwareFormat = engine.outputNode.outputFormat(forBus: 0)
        let sampleRate = hardwareFormat.sampleRate
        guard sampleRate > 0, hardwareFormat.channelCount > 0 else {
            log.notice("Route change reported an invalid format; waiting for the next notification")
            return
        }

        if sampleRate != currentSampleRate {
            currentSampleRate = sampleRate
            sb_engine_set_sample_rate(state, sampleRate)
            rebuildBank(sampleRate: sampleRate)
        }

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate,
                                         channels: max(1, min(hardwareFormat.channelCount, 2))) else {
            lastError = "Could not create audio format after route change"
            return
        }

        // Reconnect the existing node rather than detaching and rebuilding it.
        // Detaching invalidates the node the render block was built around and
        // is far more fragile mid-route-change.
        if let node = sourceNode {
            engine.disconnectNodeOutput(node)
            engine.connect(node, to: engine.outputNode, format: format)
        } else {
            buildGraph()
        }

        // Publish before starting, so the render thread never observes the new
        // sample rate alongside pointers into the retired bank.
        publishParams()
        startGraph()
        releaseRetiredBanks()
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

    /// Sets one mix bus. Takes effect on the next render, so it is safe to drag
    /// a slider while the click is running.
    public func setLevelGain(_ gain: Double, for level: SBAccentLevel) {
        let index = Int(level.rawValue)
        guard levelGains.indices.contains(index) else { return }
        levelGains[index] = Float(max(0, min(gain, 2)))
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
        let levels = pattern.levels
        let framesPerTick = pattern.framesPerTick(bpm: bpm, sampleRate: currentSampleRate)

        levels.withUnsafeBufferPointer { levelsPtr in
            sounds.withUnsafeMutableBufferPointer { soundsPtr in
                levelGains.withUnsafeBufferPointer { gainsPtr in
                    sb_publish_params(
                        state,
                        framesPerTick,
                        UInt32(levels.count),
                        UInt32(pattern.ticksPerBeat),
                        levelsPtr.baseAddress,
                        soundsPtr.baseAddress,
                        gainsPtr.baseAddress
                    )
                }
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
