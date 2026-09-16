import Foundation
import SelahBeatCore
import SelahBeatAudioC

func name(_ l: UInt8) -> String {
    switch UInt32(l) {
    case SB_LEVEL_SILENT.rawValue: return "."
    case SB_LEVEL_DOWNBEAT.rawValue: return "D"
    case SB_LEVEL_ACCENT.rawValue: return "A"
    case SB_LEVEL_QUARTER.rawValue: return "q"
    case SB_LEVEL_EIGHTH.rawValue: return "e"
    default: return "s"
    }
}

@MainActor func dumpMeters() {
for sub in [Subdivision.quarter, .eighth] {
    print("=== subdivision \(sub.label) ===")
    for ts in TimeSignature.common {
        let p = ClickPattern.standard(for: ts, subdivision: sub)
        let secondsPerBar = Double(p.ticksPerBar) * p.framesPerTick(bpm: 120, sampleRate: 48000) / 48000
        let audible = p.levels.filter { UInt32($0) == SB_LEVEL_DOWNBEAT.rawValue || UInt32($0) == SB_LEVEL_QUARTER.rawValue || UInt32($0) == SB_LEVEL_ACCENT.rawValue }.count
        print(String(format: "%-5@ tpb=%d ticks=%2d bar=%.3fs audible@stdmix=%d  %@",
                     ts.display as NSString, p.ticksPerBeat, p.ticksPerBar, secondsPerBar, audible,
                     p.levels.map(name).joined() as NSString))
    }
}
}
