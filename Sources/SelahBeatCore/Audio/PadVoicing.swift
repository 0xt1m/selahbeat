import Foundation
import SelahBeatAudioC

/// The chord a pad plays for a key, as frequencies and gains.
///
/// Voiced the way a keyboard player would sit one under a band: root low,
/// fifth and octave above it, the third quiet enough that it never fights a
/// vocal, and every note doubled slightly out of tune so the chord moves
/// instead of sitting still.
public struct PadVoicing: Sendable {
    public let frequencies: [Float]
    public let gains: [Float]

    public static let voiceLimit = Int(SB_PAD_VOICES)

    /// Semitones above C for a key's tonic.
    static func semitone(for key: MusicalKey) -> Int {
        let base: [MusicalKey.Letter: Int] = [.C: 0, .D: 2, .E: 4, .F: 5, .G: 7, .A: 9, .B: 11]
        var value = base[key.letter] ?? 0
        switch key.accidental {
        case .flat: value -= 1
        case .sharp: value += 1
        case .natural: break
        }
        return ((value % 12) + 12) % 12
    }

    /// A4 = 440 Hz, and everything else counted from it.
    static func frequency(semitonesAboveC: Int, octave: Int) -> Double {
        // MIDI note 60 is middle C; 69 is A4.
        let midi = 12 * (octave + 1) + semitonesAboveC
        return 440.0 * pow(2.0, (Double(midi) - 69.0) / 12.0)
    }

    public init(key: MusicalKey) {
        let tonic = Self.semitone(for: key)
        let third = key.mode == .minor ? 3 : 4

        // Octave 2 root, so the pad sits below the click rather than around it.
        let intervals: [(semitones: Int, octave: Int, gain: Float)] = [
            (0, 2, 1.00),        // root
            (7, 2, 0.55),        // fifth
            (0, 3, 0.70),        // octave
            (third, 3, 0.38),    // third, deliberately the quietest
            (7, 3, 0.30),        // fifth above
            (0, 4, 0.16),        // a little air on top
        ]

        var frequencies: [Float] = []
        var gains: [Float] = []

        for interval in intervals {
            let hertz = Self.frequency(semitonesAboveC: tonic + interval.semitones, octave: interval.octave)
            // Each note twice, a few cents apart: the beating between the two
            // is what stops the chord sounding like an organ.
            frequencies.append(Float(hertz * pow(2.0, -3.5 / 1200.0)))
            gains.append(interval.gain * 0.5)
            frequencies.append(Float(hertz * pow(2.0, 3.5 / 1200.0)))
            gains.append(interval.gain * 0.5)
        }

        // Headroom: a dozen voices summing flat out would clip before the
        // level slider ever got a say.
        let total = gains.reduce(0, +)
        let scale = total > 0 ? 0.55 / total : 0
        self.frequencies = Array(frequencies.prefix(Self.voiceLimit))
        self.gains = Array(gains.prefix(Self.voiceLimit)).map { $0 * scale }
    }
}
