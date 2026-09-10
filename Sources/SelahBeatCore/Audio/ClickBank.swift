import Foundation
import SelahBeatAudioC

/// The six click timbres, in the order they appear in the picker.
public enum ClickTimbre: Int32, Codable, Sendable, CaseIterable, Identifiable {
    case sine = 0
    case woodblock = 1
    case cowbell = 2
    case stick = 3
    case rim = 4
    case pulse = 5

    public var id: Int32 { rawValue }

    public var name: String {
        switch self {
        case .sine: return "Beep"
        case .woodblock: return "Woodblock"
        case .cowbell: return "Cowbell"
        case .stick: return "Stick"
        case .rim: return "Rim"
        case .pulse: return "Soft Pulse"
        }
    }

    public var detail: String {
        switch self {
        case .sine: return "Classic electronic click"
        case .woodblock: return "Dry and percussive"
        case .cowbell: return "Cuts through a loud stage"
        case .stick: return "Sharp attack, very short"
        case .rim: return "Ringing tick"
        case .pulse: return "Gentle \u{2014} easiest on in-ears"
        }
    }

    var cValue: SBTimbre { SBTimbre(rawValue: UInt32(rawValue)) }
}

/// All click sounds for one sample rate, pre-rendered into a single arena.
///
/// Every timbre is rendered up front — about 2 MB — so changing the click
/// sound is a parameter publish rather than an allocation, and can therefore
/// happen while the metronome is running without a glitch.
public final class ClickBank: @unchecked Sendable {
    private let arena: OpaquePointer
    public let sampleRate: Double
    /// [timbre][accent level]
    private var sounds: [[SBSoundRef]]

    public init?(sampleRate: Double) {
        self.sampleRate = sampleRate

        // Generous: every timbre, every level, half a second each.
        let capacity = Int(Double(ClickTimbre.allCases.count) * Double(SB_ACCENT_LEVELS) * sampleRate * 0.5)
        guard let arena = sb_arena_create(capacity) else { return nil }
        self.arena = arena

        var built: [[SBSoundRef]] = []
        built.reserveCapacity(ClickTimbre.allCases.count)
        for timbre in ClickTimbre.allCases {
            var perLevel: [SBSoundRef] = []
            perLevel.reserveCapacity(Int(SB_ACCENT_LEVELS))
            for level in 0..<Int(SB_ACCENT_LEVELS) {
                perLevel.append(sb_synth_render(arena, timbre.cValue, Int32(level), sampleRate))
            }
            built.append(perLevel)
        }
        self.sounds = built
    }

    deinit {
        sb_arena_destroy(arena)
    }

    /// The five accent-level sounds for one timbre, ready to publish.
    public func sounds(for timbre: ClickTimbre) -> [SBSoundRef] {
        let index = Int(timbre.rawValue)
        guard sounds.indices.contains(index) else {
            return Array(repeating: SBSoundRef(samples: nil, length: 0, gain: 0), count: Int(SB_ACCENT_LEVELS))
        }
        return sounds[index]
    }
}
