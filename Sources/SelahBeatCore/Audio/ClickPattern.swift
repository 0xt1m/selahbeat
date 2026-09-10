import Foundation
import SelahBeatAudioC

/// How many ticks a beat is divided into.
public enum Subdivision: Int, Codable, Sendable, CaseIterable, Identifiable {
    case quarter = 1
    case eighth = 2
    case triplet = 3
    case sixteenth = 4

    public var id: Int { rawValue }

    public var label: String {
        switch self {
        case .quarter: return "Quarter"
        case .eighth: return "Eighth"
        case .triplet: return "Triplet"
        case .sixteenth: return "16th"
        }
    }

    public var symbol: String {
        switch self {
        case .quarter: return "\u{2669}"
        case .eighth: return "\u{266B}"
        case .triplet: return "\u{266B}3"
        case .sixteenth: return "\u{266C}"
        }
    }
}

/// The tick table handed to the render thread.
///
/// Every meter — simple, compound, or odd — reduces to the same mechanism:
/// an array of accent levels, one per tick, and a frame count per tick. The
/// render loop just indexes into it, so there is no meter-specific branching
/// on the audio thread.
public struct ClickPattern: Hashable, Sendable {
    public var levels: [UInt8]
    public var ticksPerBeat: Int

    public var ticksPerBar: Int { levels.count }

    public init(levels: [UInt8], ticksPerBeat: Int) {
        self.levels = levels
        self.ticksPerBeat = max(1, ticksPerBeat)
    }

    /// The default pattern for a meter. The user can override any tick.
    public static func standard(for signature: TimeSignature, subdivision: Subdivision) -> ClickPattern {
        if signature.isCompound {
            // 6/8, 9/8, 12/8 felt in dotted-quarter pulses. The pulse is the
            // beat; the three eighths inside it are the subdivision.
            let pulses = signature.pulseCount
            if subdivision == .quarter {
                var levels = [UInt8](repeating: UInt8(SB_LEVEL_BEAT.rawValue), count: pulses)
                levels[0] = UInt8(SB_LEVEL_DOWNBEAT.rawValue)
                return ClickPattern(levels: levels, ticksPerBeat: 1)
            }
            var levels: [UInt8] = []
            for pulse in 0..<pulses {
                levels.append(pulse == 0 ? UInt8(SB_LEVEL_DOWNBEAT.rawValue) : UInt8(SB_LEVEL_BEAT.rawValue))
                levels.append(UInt8(SB_LEVEL_SUBDIVISION.rawValue))
                levels.append(UInt8(SB_LEVEL_SUBDIVISION.rawValue))
            }
            return ClickPattern(levels: levels, ticksPerBeat: 3)
        }

        let ticksPerBeat = subdivision.rawValue
        var levels: [UInt8] = []
        for beat in 0..<signature.beats {
            for tick in 0..<ticksPerBeat {
                if tick != 0 {
                    levels.append(UInt8(SB_LEVEL_SUBDIVISION.rawValue))
                } else if beat == 0 {
                    levels.append(UInt8(SB_LEVEL_DOWNBEAT.rawValue))
                } else {
                    levels.append(UInt8(SB_LEVEL_BEAT.rawValue))
                }
            }
        }
        return ClickPattern(levels: levels, ticksPerBeat: ticksPerBeat)
    }

    /// Frames between ticks. `bpm` is the pulse tempo the drummer counts.
    public func framesPerTick(bpm: Double, sampleRate: Double) -> Double {
        let safeBPM = max(1.0, bpm)
        return sampleRate * 60.0 / (safeBPM * Double(ticksPerBeat))
    }

    /// Cycles a tick through silent -> beat -> accent, leaving the downbeat
    /// alone unless explicitly muted.
    public mutating func cycleLevel(at index: Int) {
        guard levels.indices.contains(index) else { return }
        let isBeat = index % ticksPerBeat == 0
        let current = Int(levels[index])
        let order: [Int] = isBeat
            ? [Int(SB_LEVEL_BEAT.rawValue), Int(SB_LEVEL_ACCENT.rawValue), Int(SB_LEVEL_SILENT.rawValue)]
            : [Int(SB_LEVEL_SUBDIVISION.rawValue), Int(SB_LEVEL_ACCENT.rawValue), Int(SB_LEVEL_SILENT.rawValue)]
        if index == 0 {
            let downbeatOrder = [Int(SB_LEVEL_DOWNBEAT.rawValue), Int(SB_LEVEL_SILENT.rawValue)]
            let idx = downbeatOrder.firstIndex(of: current) ?? 0
            levels[index] = UInt8(downbeatOrder[(idx + 1) % downbeatOrder.count])
            return
        }
        let idx = order.firstIndex(of: current) ?? 0
        levels[index] = UInt8(order[(idx + 1) % order.count])
    }
}
