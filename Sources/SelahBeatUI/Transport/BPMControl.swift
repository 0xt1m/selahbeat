import SwiftUI
import SelahBeatCore

/// Big tempo readout with nudge controls and a drag-to-scrub gesture.
public struct BPMControl: View {
    private let controller: MetronomeController
    private let size: CGFloat

    @State private var dragAccumulator: Double = 0

    public init(controller: MetronomeController, size: CGFloat = 52) {
        self.controller = controller
        self.size = size
    }

    public var body: some View {
        HStack(spacing: 10) {
            nudgeButton(systemName: "minus", delta: -1)

            VStack(spacing: 0) {
                Text(display)
                    .font(Theme.tempoFont(size: size))
                    .foregroundStyle(Theme.primaryText)
                    .contentTransition(.numericText())
                Text("BPM")
                    .font(.system(size: size * 0.22, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .kerning(1.2)
            }
            .frame(minWidth: size * 2.6)
            .contentShape(Rectangle())
            .gesture(scrubGesture)
            .accessibilityLabel("Tempo")
            .accessibilityValue("\(Int(controller.bpm)) beats per minute")
            .accessibilityAdjustableAction { direction in
                controller.nudge(direction == .increment ? 1 : -1)
            }

            nudgeButton(systemName: "plus", delta: 1)
        }
    }

    private var display: String {
        let bpm = controller.bpm
        return bpm == bpm.rounded() ? String(Int(bpm)) : String(format: "%.1f", bpm)
    }

    /// Vertical drag scrubs tempo — faster than repeated taps when hunting for
    /// a feel, and it works while the click is running.
    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let steps = (-value.translation.height / 6.0) - dragAccumulator
                if abs(steps) >= 1 {
                    let whole = steps.rounded(.towardZero)
                    controller.nudge(whole)
                    dragAccumulator += whole
                }
            }
            .onEnded { _ in dragAccumulator = 0 }
    }

    private func nudgeButton(systemName: String, delta: Double) -> some View {
        InstantButton {
            controller.nudge(delta)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: size * 0.3, weight: .bold))
                .foregroundStyle(Theme.primaryText)
                .frame(width: Theme.minHitTarget, height: Theme.minHitTarget)
                .background(Theme.surfaceRaised, in: Circle())
                .contentShape(Circle())
        }
        .accessibilityLabel(delta > 0 ? "Increase tempo" : "Decrease tempo")
    }
}
