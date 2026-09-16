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
    ///
    /// Each tick is labelled by what it *is* musically - quarter, eighth,
    /// sixteenth - rather than just "beat or not", so each can be mixed
    /// independently.
    public static func standard(for signature: TimeSignature, subdivision: Subdivision) -> ClickPattern {
        // Meters written over 8 click the eighth note, and the tempo means
        // eighth notes. Every eighth sounds; the first of each group is
        // accented, which is what makes 6/8 read as 6/8 and not as 3/4, and
        // 7/8 as 2+2+3 rather than seven flat clicks.
        //
        // Before this, 7/8 clicked seven *quarters* - a bar took twice as long
        // as it should - and 6/8 clicked only its two dotted-quarter pulses,
        // so the same tempo number meant a different speed in every meter.
        if signature.noteValue == 8 {
            // Two ticks per eighth, so the sixteenth mix bus still has
            // somewhere to sound, exactly as in the straight meters below.
            let ticksPerBeat = 2
            let groups = signature.eighthGrouping
            var levels: [UInt8] = []
            var eighth = 0
            for group in groups {
                for positionInGroup in 0..<group {
                    let level: SBAccentLevel
                    if eighth == 0 {
                        level = SB_LEVEL_DOWNBEAT          // bar start
                    } else if positionInGroup == 0 {
                        level = SB_LEVEL_ACCENT            // start of 2 or 3
                    } else {
                        level = SB_LEVEL_QUARTER           // the eighths between
                    }
                    levels.append(UInt8(level.rawValue))
                    for _ in 1..<ticksPerBeat {
                        levels.append(UInt8(SB_LEVEL_SIXTEENTH.rawValue))
                    }
                    eighth += 1
                }
            }
            return ClickPattern(levels: levels, ticksPerBeat: ticksPerBeat)
        }

        // Straight meters are always laid out on a sixteenth grid, whatever
        // the subdivision picker says. The mix busses then decide which layers
        // are audible, so unmuting "eighth notes" adds the offbeats rather than
        // doing nothing because the pattern had no room for them.
        //
        // Triplets cannot live on a sixteenth grid, so they keep their own.
        let ticksPerBeat = subdivision == .triplet ? 3 : 4
        var levels: [UInt8] = []
        for beat in 0..<signature.beats {
            for tick in 0..<ticksPerBeat {
                levels.append(UInt8(levelFor(tick: tick, ticksPerBeat: ticksPerBeat,
                                            isFirstBeat: beat == 0).rawValue))
            }
        }
        return ClickPattern(levels: levels, ticksPerBeat: ticksPerBeat)
    }

    /// Which mix bus a tick belongs to, from its position within the beat.
    ///
    /// With sixteenth subdivision the offbeat eighth (position 2 of 4) is an
    /// eighth note, while positions 1 and 3 are sixteenths - so they land on
    /// different busses, which is what makes separate volumes meaningful.
    /// Triplets have no sixteenths, so their inner ticks use the eighth bus.
    static func levelFor(tick: Int, ticksPerBeat: Int, isFirstBeat: Bool) -> SBAccentLevel {
        if tick == 0 {
            return isFirstBeat ? SB_LEVEL_DOWNBEAT : SB_LEVEL_QUARTER
        }
        switch ticksPerBeat {
        case 4:  return tick == 2 ? SB_LEVEL_EIGHTH : SB_LEVEL_SIXTEENTH
        // An x/8 meter's beat is already an eighth, so what sits between two
        // ticks of it is a sixteenth.
        case 2:  return SB_LEVEL_SIXTEENTH
        default: return SB_LEVEL_EIGHTH
        }
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
        let current = Int(levels[index])

        if index == 0 {
            let order = [Int(SB_LEVEL_DOWNBEAT.rawValue), Int(SB_LEVEL_SILENT.rawValue)]
            let idx = order.firstIndex(of: current) ?? 0
            levels[index] = UInt8(order[(idx + 1) % order.count])
            return
        }

        // Cycling returns a tick to its natural bus, so muting and unmuting
        // never silently moves a sixteenth onto the eighth mix.
        let natural = Int(ClickPattern.levelFor(tick: index % ticksPerBeat,
                                                ticksPerBeat: ticksPerBeat,
                                                isFirstBeat: false).rawValue)
        let order = [natural, Int(SB_LEVEL_ACCENT.rawValue), Int(SB_LEVEL_SILENT.rawValue)]
        let idx = order.firstIndex(of: current) ?? 0
        levels[index] = UInt8(order[(idx + 1) % order.count])
    }
}
