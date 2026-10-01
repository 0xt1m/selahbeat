import Foundation
import SelahBeatAudioC

/// The pad voices, described the way a worship musician would choose between
/// them rather than by their harmonic content.
public enum PadSound: Int, Codable, Sendable, CaseIterable, Identifiable {
    case warm = 0
    case strings = 1
    case glass = 2
    case air = 3
    case organ = 4

    public var id: Int { rawValue }

    public var name: String {
        switch self {
        case .warm: return "Warm"
        case .strings: return "Strings"
        case .glass: return "Glass"
        case .air: return "Air"
        case .organ: return "Organ"
        }
    }

    public var detail: String {
        switch self {
        case .warm: return "Soft and round \u{2014} the safe one"
        case .strings: return "Bowed, with more movement"
        case .glass: return "Clean and bright"
        case .air: return "Barely there, under everything"
        case .organ: return "Steady and present"
        }
    }

    /// How hard the one-pole lowpass is driven. Part of the voice: Air is
    /// filtered until almost nothing is left of the harmonics, Glass hardly at
    /// all.
    var filterCoefficient: Float {
        switch self {
        case .warm: return 0.25
        case .strings: return 0.45
        case .glass: return 0.70
        case .air: return 0.12
        case .organ: return 0.50
        }
    }

    var cValue: SBPadVoice { SBPadVoice(rawValue: UInt32(rawValue)) }
}
