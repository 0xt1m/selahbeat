import Foundation

/// A time signature as a musician writes it: a numerator and a note value.
public struct TimeSignature: Hashable, Codable, Sendable {
    public var beats: Int      // numerator
    public var noteValue: Int  // denominator: 2, 4, 8, 16

    public init(beats: Int, noteValue: Int) {
        self.beats = max(1, min(beats, 32))
        self.noteValue = [2, 4, 8, 16].contains(noteValue) ? noteValue : 4
    }

    public static let fourFour = TimeSignature(beats: 4, noteValue: 4)
    public static let threeFour = TimeSignature(beats: 3, noteValue: 4)
    public static let sixEight = TimeSignature(beats: 6, noteValue: 8)

    /// 6/8, 9/8, 12/8 — felt in dotted-quarter pulses, not eighths.
    public var isCompound: Bool {
        noteValue == 8 && beats % 3 == 0 && beats > 3
    }

    /// How many pulses a drummer actually counts in a bar.
    public var pulseCount: Int {
        isCompound ? beats / 3 : beats
    }

    public var display: String { "\(beats)/\(noteValue)" }

    /// Common meters, in the order a worship drummer is likely to want them.
    public static let common: [TimeSignature] = [
        .fourFour,
        .threeFour,
        TimeSignature(beats: 2, noteValue: 4),
        .sixEight,
        TimeSignature(beats: 12, noteValue: 8),
        TimeSignature(beats: 5, noteValue: 4),
        TimeSignature(beats: 7, noteValue: 8),
        TimeSignature(beats: 9, noteValue: 8),
    ]
}
