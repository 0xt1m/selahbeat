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

    /// How the eighths of an x/8 bar are grouped, which is what the accents
    /// mark: 6/8 as 3+3, 7/8 as 2+2+3, 5/8 as 2+3.
    ///
    /// Threes where they divide evenly; otherwise twos first and a three at
    /// the end, which is how these meters are almost always counted.
    public var eighthGrouping: [Int] {
        guard noteValue == 8 else { return Array(repeating: 1, count: beats) }
        if beats % 3 == 0 { return Array(repeating: 3, count: beats / 3) }

        var groups: [Int] = []
        var remaining = beats
        while remaining % 3 != 0 && remaining > 3 {
            groups.append(2)
            remaining -= 2
        }
        if remaining % 3 == 0 {
            groups.append(contentsOf: Array(repeating: 3, count: remaining / 3))
        } else if remaining > 0 {
            groups.append(remaining)
        }
        return groups
    }

    /// The pulse a bar is felt in, for display. An x/8 meter clicks eighths,
    /// so what a drummer feels is the group count: 6/8 in 2, 7/8 in 3.
    public var groupCount: Int {
        noteValue == 8 ? eighthGrouping.count : beats
    }

    public var display: String { "\(beats)/\(noteValue)" }

    /// Common meters, in the order a worship drummer is likely to want them.
    public static let common: [TimeSignature] = [
        .fourFour,
        .threeFour,
        TimeSignature(beats: 2, noteValue: 4),
        // One beat per bar: every click is a downbeat. Useful for counting in
        // a free section, or for practising against a single pulse.
        TimeSignature(beats: 1, noteValue: 4),
        .sixEight,
        TimeSignature(beats: 12, noteValue: 8),
        TimeSignature(beats: 5, noteValue: 4),
        TimeSignature(beats: 7, noteValue: 8),
        TimeSignature(beats: 9, noteValue: 8),
    ]
}
