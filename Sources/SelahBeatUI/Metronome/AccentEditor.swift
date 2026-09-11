import SwiftUI
import SelahBeatCore

/// Accent editing laid out one row per beat.
///
/// A single row of dots cannot work: on a sixteenth grid, 4/4 is sixteen dots
/// and 7/8 is twenty-eight. At a tappable size that is far wider than a phone,
/// and an over-wide row does not just look cramped - it widens the whole
/// column and pushes the rest of the screen off the edge.
///
/// A grid of `ticksPerBeat` columns fixes the width at four dots regardless of
/// meter, and reads the way a drummer counts: each row is one beat.
public struct AccentEditor: View {
    private let controller: MetronomeController
    private let dotSize: CGFloat

    public init(controller: MetronomeController, dotSize: CGFloat = 18) {
        self.controller = controller
        self.dotSize = dotSize
    }

    private var pattern: ClickPattern { controller.pattern }
    private var ticksPerBeat: Int { max(1, pattern.ticksPerBeat) }
    private var beatCount: Int {
        Int((Double(pattern.ticksPerBar) / Double(ticksPerBeat)).rounded(.up))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(0..<beatCount, id: \.self) { beat in
                HStack(spacing: 10) {
                    Text("\(beat + 1)")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Theme.secondaryText.opacity(0.7))
                        .frame(width: 14, alignment: .trailing)

                    ForEach(0..<ticksPerBeat, id: \.self) { offset in
                        let index = beat * ticksPerBeat + offset
                        if index < pattern.levels.count {
                            dot(at: index, isBeatStart: offset == 0)
                        } else {
                            Color.clear.frame(width: dotSize, height: dotSize)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func dot(at index: Int, isBeatStart: Bool) -> some View {
        let level = pattern.levels[index]
        let size = isBeatStart ? dotSize : dotSize * 0.66

        return Button {
            controller.cycleAccent(at: index)
        } label: {
            ZStack {
                Circle()
                    .fill(fill(level))
                    .frame(width: size, height: size)
                if level == 0 {
                    Circle()
                        .strokeBorder(Theme.secondaryText.opacity(0.45), lineWidth: 1)
                        .frame(width: size, height: size)
                }
            }
            // A generous, uniform hit target regardless of the drawn size, so
            // the sixteenths are still comfortably tappable on a phone.
            .frame(width: dotSize * 1.5, height: dotSize * 1.5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(level: level, index: index))
    }

    private func fill(_ level: UInt8) -> Color {
        switch level {
        case 0: return .clear
        case 1: return Theme.accent
        case 2: return Theme.accent.opacity(0.75)
        case 3: return Theme.primaryText.opacity(0.55)
        case 4: return Theme.secondaryText.opacity(0.6)
        default: return Theme.secondaryText.opacity(0.35)
        }
    }

    private func accessibilityLabel(level: UInt8, index: Int) -> String {
        let name: String
        switch level {
        case 0: name = "muted"
        case 1: name = "downbeat"
        case 2: name = "accented"
        case 3: name = "quarter note"
        case 4: name = "eighth note"
        default: name = "sixteenth note"
        }
        return "Tick \(index + 1), \(name). Tap to change."
    }
}
