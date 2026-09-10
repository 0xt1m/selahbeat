import Foundation

/// Turns a series of taps into a tempo estimate.
///
/// Pure and synchronous so it can be unit-tested without any audio hardware.
/// Feed it timestamps from `CACurrentMediaTime()` captured as early as possible
/// in the input handler — never `Date()`, which is subject to clock adjustment.
public struct TapTempo: Sendable {
    /// A gap longer than this starts a new tap sequence rather than polluting
    /// the estimate with a stale interval.
    public var resetInterval: TimeInterval = 2.5
    /// Intervals this far from the running median are treated as a fumble.
    public var outlierTolerance: Double = 0.35
    public var maxTaps: Int = 8

    private var timestamps: [TimeInterval] = []

    public init() {}

    public var tapCount: Int { timestamps.count }

    /// Confidence in the current estimate, 0...1. Shown in the UI so a drummer
    /// knows whether to keep tapping.
    public var confidence: Double {
        guard timestamps.count >= 2 else { return 0 }
        return min(1.0, Double(timestamps.count - 1) / 4.0)
    }

    public mutating func reset() {
        timestamps.removeAll(keepingCapacity: true)
    }

    /// Records a tap. Returns the new BPM estimate, or nil if this was the
    /// first tap of a sequence.
    @discardableResult
    public mutating func tap(at time: TimeInterval) -> Double? {
        if let last = timestamps.last, time - last > resetInterval {
            timestamps.removeAll(keepingCapacity: true)
        }
        timestamps.append(time)
        if timestamps.count > maxTaps {
            timestamps.removeFirst(timestamps.count - maxTaps)
        }
        return estimate()
    }

    public func estimate() -> Double? {
        guard timestamps.count >= 2 else { return nil }

        var intervals: [Double] = []
        intervals.reserveCapacity(timestamps.count - 1)
        for i in 1..<timestamps.count {
            let d = timestamps[i] - timestamps[i - 1]
            if d > 0 { intervals.append(d) }
        }
        guard !intervals.isEmpty else { return nil }

        // Reject fumbled taps against the median before averaging.
        let sorted = intervals.sorted()
        let median = sorted[sorted.count / 2]
        let kept = intervals.filter { abs($0 - median) / median <= outlierTolerance }
        let usable = kept.isEmpty ? intervals : kept

        // Weight recent intervals more heavily so speeding up or slowing down
        // is followed rather than averaged away.
        var weightedSum = 0.0
        var weightTotal = 0.0
        for (i, interval) in usable.enumerated() {
            let w = Double(i + 1)
            weightedSum += interval * w
            weightTotal += w
        }
        guard weightTotal > 0 else { return nil }

        let averageInterval = weightedSum / weightTotal
        guard averageInterval > 0 else { return nil }

        return Song.clampBPM(60.0 / averageInterval)
    }
}
