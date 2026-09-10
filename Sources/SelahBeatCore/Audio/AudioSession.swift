import Foundation
import AVFoundation

#if os(iOS)
import UIKit
#endif

/// Platform audio configuration. macOS has no AVAudioSession, so the two
/// platforms are kept behind this seam rather than scattering #if through the
/// engine.
public protocol AudioSessionConfiguring: AnyObject, Sendable {
    func activate(preferredBufferFrames: Int) throws
    func deactivate()
    var outputLatency: TimeInterval { get }
    var routeDescription: String { get }
    /// False for Bluetooth A2DP, which adds 150-300 ms no engineering can fix.
    var isLowLatencyRoute: Bool { get }
}

#if os(macOS)

public final class MacAudioSession: AudioSessionConfiguring, @unchecked Sendable {
    public init() {}

    public func activate(preferredBufferFrames: Int) throws {
        // Nothing to activate on macOS; buffer size is applied to the output
        // unit by MetronomeEngine once the engine exists.
    }

    public func deactivate() {}

    public var outputLatency: TimeInterval = 0
    public var routeDescription: String = "System output"
    public var isLowLatencyRoute: Bool = true
}

#elseif os(iOS)

public final class IOSAudioSession: AudioSessionConfiguring, @unchecked Sendable {
    /// Set true for drummers running backing tracks from another app.
    public var allowsOtherAudio: Bool = false

    public init() {}

    public func activate(preferredBufferFrames: Int) throws {
        let session = AVAudioSession.sharedInstance()
        var options: AVAudioSession.CategoryOptions = []
        if allowsOtherAudio { options.insert(.mixWithOthers) }

        // .default rather than .measurement: measurement targets input-chain
        // neutrality and can reduce output level without buying latency for a
        // playback-only app.
        try session.setCategory(.playback, mode: .default, options: options)
        try session.setPreferredSampleRate(48_000)
        try session.setPreferredIOBufferDuration(Double(preferredBufferFrames) / 48_000.0)
        try session.setActive(true)
    }

    public func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    public var outputLatency: TimeInterval {
        AVAudioSession.sharedInstance().outputLatency
    }

    public var routeDescription: String {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        return outputs.first?.portName ?? "Unknown"
    }

    public var isLowLatencyRoute: Bool {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        let slow: Set<AVAudioSession.Port> = [.bluetoothA2DP, .bluetoothLE, .bluetoothHFP]
        return !outputs.contains { slow.contains($0.portType) }
    }
}

#endif
