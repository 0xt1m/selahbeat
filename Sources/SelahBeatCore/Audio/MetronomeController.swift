import Foundation
import Observation
import AVFoundation
import QuartzCore
import OSLog

#if os(iOS)
import UIKit
#endif

/// The main-actor facade the UI talks to. Owns tempo, meter, sound and
/// transport state, and keeps the engine in sync.
@MainActor
@Observable
public final class MetronomeController {
    private let engine: MetronomeEngine
    private var tapTempo = TapTempo()
    private let log = Logger(subsystem: "app.selahbeat", category: "metronome")

    public private(set) var isRunning: Bool = false

    /// Read-only from outside; go through `setTempo` so clamping can never be
    /// bypassed.
    ///
    /// Deliberately NOT a `didSet` that clamps by re-assigning itself: the
    /// @Observable macro rewrites stored properties into computed ones, so
    /// assigning inside the property's own `didSet` re-enters the setter and
    /// recurses until the stack overflows.
    public private(set) var bpm: Double = 120

    public func setTempo(_ newValue: Double) {
        let clamped = Song.clampBPM(newValue)
        guard clamped != bpm else { return }
        bpm = clamped
        engine.setTempo(clamped)
    }

    public var timeSignature: TimeSignature = .fourFour {
        didSet {
            guard timeSignature != oldValue else { return }
            regeneratePattern()
        }
    }

    public var subdivision: Subdivision = .quarter {
        didSet {
            guard subdivision != oldValue else { return }
            regeneratePattern()
        }
    }

    public var timbre: ClickTimbre = .woodblock {
        didSet {
            guard timbre != oldValue else { return }
            engine.setTimbre(timbre)
        }
    }

    public var masterGain: Double = 0.8 {
        didSet {
            guard masterGain != oldValue else { return }
            engine.setMasterGain(Float(masterGain))
        }
    }

    /// The accent table. Editable per tick from the UI.
    public private(set) var pattern: ClickPattern = .standard(for: .fourFour, subdivision: .quarter)

    /// What the transport is currently loaded with, if it came from a service.
    public private(set) var loadedItem: ResolvedItem?
    public private(set) var loadedServiceID: UUID?

    public private(set) var tapConfidence: Double = 0
    public private(set) var diagnostics = AudioDiagnostics()

    /// True when the output route adds latency no engineering can remove.
    public var isBluetoothWarningActive: Bool { !diagnostics.isLowLatencyRoute }

    public init(engine: MetronomeEngine) {
        self.engine = engine
        engine.setTempo(bpm)
        engine.setPattern(pattern)
        engine.setTimbre(timbre)
        engine.setMasterGain(Float(masterGain))
        observeAudioNotifications()
    }

    public static func live() -> MetronomeController {
        #if os(macOS)
        let session = MacAudioSession()
        #else
        let session = IOSAudioSession()
        #endif
        let engine = MetronomeEngine(session: session)
        engine.startEngine()
        let controller = MetronomeController(engine: engine)
        controller.refreshDiagnostics()
        return controller
    }

    // MARK: - Transport

    /// Called from press-down, not press-up. See InstantButtonStyle.
    public func start() {
        engine.start()
        isRunning = true
        setIdleTimerDisabled(true)
    }

    public func stop() {
        engine.stop()
        isRunning = false
        setIdleTimerDisabled(false)
    }

    public func toggle() {
        if isRunning { stop() } else { start() }
    }

    // MARK: - Tap tempo

    /// Pass a `CACurrentMediaTime()` captured as early as possible in the
    /// input handler.
    public func tap(at time: TimeInterval = CACurrentMediaTime()) {
        if let estimate = tapTempo.tap(at: time) {
            setTempo(estimate.rounded())
        }
        tapConfidence = tapTempo.confidence
    }

    public func resetTap() {
        tapTempo.reset()
        tapConfidence = 0
    }

    // MARK: - Tempo nudging

    public func nudge(_ delta: Double) {
        setTempo(bpm + delta)
    }

    // MARK: - Accents

    public func cycleAccent(at index: Int) {
        var updated = pattern
        updated.cycleLevel(at: index)
        pattern = updated
        engine.setPattern(updated)
    }

    public func resetAccents() {
        regeneratePattern()
    }

    private func regeneratePattern() {
        pattern = .standard(for: timeSignature, subdivision: subdivision)
        engine.setPattern(pattern)
    }

    // MARK: - Loading songs

    /// Loads a song's tempo, meter and key into the transport. Deliberately
    /// does NOT auto-start — auto-starting mid-service would be a disaster.
    public func load(_ resolved: ResolvedItem, serviceID: UUID? = nil) {
        loadedItem = resolved
        loadedServiceID = serviceID
        setTempo(resolved.bpm)
        timeSignature = resolved.timeSignature
        regeneratePattern()
    }

    public func loadSong(_ song: Song) {
        load(ResolvedItem(item: ServiceItem(songID: song.id), song: song))
    }

    public func clearLoaded() {
        loadedItem = nil
        loadedServiceID = nil
    }

    // MARK: - Sound preview

    public func previewTimbre(_ newTimbre: ClickTimbre) {
        timbre = newTimbre
        if !isRunning {
            engine.preview(newTimbre)
        }
    }

    // MARK: - Beat indicator

    /// Which tick most recently sounded, corrected for output latency so the
    /// visual lines up with what is heard. On a Bluetooth route the correction
    /// is 150 ms or more and very visible if omitted.
    public func currentTickInBar(now: TimeInterval = CACurrentMediaTime()) -> Int? {
        guard isRunning else { return nil }
        let tick = engine.lastTick()
        guard tick.tickIndex > 0 else { return nil }

        let hostSeconds = MetronomeController.hostTimeToSeconds(tick.hostTime)
        let audibleAt = hostSeconds + engine.outputLatency
        // Only light up if the tick is recent; otherwise the dot would stick on
        // after a stop.
        guard now >= audibleAt, now - audibleAt < 2.0 else { return nil }
        return Int(tick.tickInBar)
    }

    /// How long ago the last tick was heard, for flash decay.
    public func secondsSinceLastTick(now: TimeInterval = CACurrentMediaTime()) -> TimeInterval? {
        let tick = engine.lastTick()
        guard tick.tickIndex > 0 else { return nil }
        let audibleAt = MetronomeController.hostTimeToSeconds(tick.hostTime) + engine.outputLatency
        let delta = now - audibleAt
        return delta >= 0 ? delta : nil
    }

    private static let hostTimeScale: Double = {
        var info = mach_timebase_info_data_t()
        guard mach_timebase_info(&info) == KERN_SUCCESS, info.denom != 0 else { return 1 }
        return Double(info.numer) / Double(info.denom) / 1_000_000_000.0
    }()

    static func hostTimeToSeconds(_ hostTime: UInt64) -> TimeInterval {
        Double(hostTime) * hostTimeScale
    }

    // MARK: - Diagnostics

    /// Monotonic count of ticks emitted, straight from the render thread.
    /// Used by the audio-check tool to verify the engine end to end.
    public var lastTickIndexForDiagnostics: UInt64 {
        engine.lastTick().tickIndex
    }

    public func refreshDiagnostics() {
        diagnostics = engine.diagnostics()
    }

    public func resetRenderStats() {
        engine.resetRenderStats()
        refreshDiagnostics()
    }

    // MARK: - Route / interruption handling

    private func observeAudioNotifications() {
        let center = NotificationCenter.default

        center.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleConfigurationChange()
            }
        }

        #if os(iOS)
        center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleConfigurationChange()
            }
        }

        center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            // Pull the Sendable value out before crossing to the main actor;
            // Notification itself is not Sendable.
            let rawType = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            MainActor.assumeIsolated {
                self?.handleInterruption(rawType: rawType)
            }
        }

        center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleConfigurationChange()
            }
        }
        #endif
    }

    private func handleConfigurationChange() {
        log.notice("Audio configuration changed; rebuilding graph")
        engine.handleConfigurationChange()
        isRunning = engine.isRunning
        refreshDiagnostics()
    }

    #if os(iOS)
    public private(set) var wasInterruptedWhileRunning = false

    private func handleInterruption(rawType: UInt?) {
        guard let raw = rawType,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            wasInterruptedWhileRunning = isRunning
            stop()
        case .ended:
            // Deliberately do NOT auto-resume. After a phone call the band is
            // no longer at that point in the song; a big Resume button is the
            // right affordance.
            engine.handleConfigurationChange()
            refreshDiagnostics()
        @unknown default:
            break
        }
    }

    public func acknowledgeInterruption() {
        wasInterruptedWhileRunning = false
    }
    #endif

    private func setIdleTimerDisabled(_ disabled: Bool) {
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = disabled
        #endif
    }
}
