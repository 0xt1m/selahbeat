import SwiftUI
import QuartzCore
import SelahBeatCore

/// The beat indicator.
///
/// Polls atomics written by the render thread rather than being pushed from it —
/// the audio thread must never dispatch, signal, or allocate. The flash is also
/// offset by the measured output latency so the dot lights when the click is
/// *heard*, not when it was rendered. On Bluetooth that gap is 150 ms+ and the
/// difference is very visible.
public struct BeatDots: View {
    /// One dot per tick (subdivisions included) or one per counted beat.
    ///
    /// The transport bar uses `.beats` because a tick-level row grows without
    /// bound — 7/8 in sixteenths is 28 dots, which is wider than a phone.
    public enum Granularity {
        case ticks
        case beats
    }

    private let controller: MetronomeController
    private let dotSize: CGFloat
    private let interactive: Bool
    private let granularity: Granularity

    public init(
        controller: MetronomeController,
        dotSize: CGFloat = 14,
        interactive: Bool = false,
        granularity: Granularity = .ticks
    ) {
        self.controller = controller
        self.dotSize = dotSize
        self.interactive = interactive
        self.granularity = granularity
    }

    private var ticksPerBeat: Int { max(1, controller.pattern.ticksPerBeat) }

    /// (tick index, accent level) for each dot actually drawn.
    private var slots: [(index: Int, level: UInt8)] {
        let levels = controller.pattern.levels
        switch granularity {
        case .ticks:
            return levels.enumerated().map { ($0.offset, $0.element) }
        case .beats:
            return stride(from: 0, to: levels.count, by: ticksPerBeat).map { ($0, levels[$0]) }
        }
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !controller.isRunning)) { _ in
            let activeTick = controller.isRunning ? controller.currentTickInBar() : nil
            let flash = flashAmount()

            HStack(spacing: dotSize * 0.55) {
                ForEach(slots, id: \.index) { slot in
                    dot(index: slot.index, level: slot.level, activeTick: activeTick, flash: flash)
                }
            }
        }
    }

    private func flashAmount() -> Double {
        guard let since = controller.secondsSinceLastTick() else { return 0 }
        // Decay the highlight over 120 ms so the dot pulses rather than blinks.
        let decay = 1.0 - min(1.0, since / 0.12)
        return max(0, decay)
    }

    /// In beats mode a dot stays lit for the whole beat, including its
    /// subdivisions, rather than going dark between them.
    private func isActive(index: Int, activeTick: Int?) -> Bool {
        guard let activeTick else { return false }
        switch granularity {
        case .ticks:
            return activeTick == index
        case .beats:
            return (activeTick / ticksPerBeat) * ticksPerBeat == index
        }
    }

    @ViewBuilder
    private func dot(index: Int, level: UInt8, activeTick: Int?, flash: Double) -> some View {
        let isBeat = index % ticksPerBeat == 0
        let isActive = isActive(index: index, activeTick: activeTick)
        let size = (isBeat || granularity == .beats) ? dotSize : dotSize * 0.6

        let shape = Circle()
            .fill(fillColor(level: level, isActive: isActive, flash: flash))
            .frame(width: size, height: size)
            .overlay {
                Circle()
                    .strokeBorder(strokeColor(level: level), lineWidth: level == 0 ? 1 : 0)
                    .frame(width: size, height: size)
            }
            .scaleEffect(isActive ? 1.0 + 0.35 * flash : 1.0)

        if interactive {
            Button {
                controller.cycleAccent(at: index)
            } label: {
                shape.frame(width: dotSize * 1.6, height: dotSize * 1.6).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Tap to change this beat's accent")
        } else {
            shape
        }
    }

    private func fillColor(level: UInt8, isActive: Bool, flash: Double) -> Color {
        if level == 0 { return .clear }
        let base: Color = level == 1 ? Theme.accent : (level == 2 ? Theme.accent.opacity(0.8) : Theme.secondaryText)
        guard isActive else { return base.opacity(level >= 4 ? 0.35 : 0.55) }
        return base.opacity(0.55 + 0.45 * flash)
    }

    private func strokeColor(level: UInt8) -> Color {
        level == 0 ? Theme.secondaryText.opacity(0.5) : .clear
    }
}
