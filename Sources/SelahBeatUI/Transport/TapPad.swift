import SwiftUI
import QuartzCore
import SelahBeatCore

/// Tap tempo. Timestamps are captured on press-down using CACurrentMediaTime,
/// not Date() — the mach clock is monotonic and not subject to time sync.
public struct TapPad: View {
    private let controller: MetronomeController
    private let compact: Bool

    @State private var pulse: Bool = false

    public init(controller: MetronomeController, compact: Bool = true) {
        self.controller = controller
        self.compact = compact
    }

    public var body: some View {
        InstantButton {
            controller.tap(at: CACurrentMediaTime())
            pulse.toggle()
        } label: {
            VStack(spacing: 2) {
                Text("TAP")
                    .font(.system(size: compact ? 15 : 22, weight: .heavy, design: .rounded))
                    .kerning(1.4)
                if !compact {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .foregroundStyle(Theme.primaryText)
            .frame(minWidth: compact ? 68 : 120, minHeight: compact ? Theme.minHitTarget : Theme.primaryButtonHeight)
            .frame(maxWidth: .infinity)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(confidenceOpacity), lineWidth: 2)
            )
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Tap tempo")
    }

    private var confidenceOpacity: Double {
        0.15 + 0.75 * controller.tapConfidence
    }

    private var hint: String {
        switch controller.tapConfidence {
        case 0: return "Tap along"
        case ..<0.5: return "Keep tapping"
        default: return "Locked in"
        }
    }
}
