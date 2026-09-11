import SwiftUI
import SelahBeatCore

/// The one control that has to be right. Large, unmissable, and wired to fire
/// on press-down so the click starts under the finger.
public struct StartStopButton: View {
    private let controller: MetronomeController
    private let height: CGFloat
    /// The transport bar drops the word and keeps just the glyph — the icon
    /// already says which state it is in, and the space is better spent on the
    /// tap target.
    private let showsLabel: Bool

    public init(
        controller: MetronomeController,
        height: CGFloat = Theme.primaryButtonHeight,
        showsLabel: Bool = true
    ) {
        self.controller = controller
        self.height = height
        self.showsLabel = showsLabel
    }

    private var title: String { controller.isRunning ? "STOP" : "START" }
    private var symbol: String { controller.isRunning ? "stop.fill" : "play.fill" }

    public var body: some View {
        InstantButton {
            controller.toggle()
        } label: {
            content
                .foregroundStyle(controller.isRunning ? Color.black : Theme.primaryText)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(
                    RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                        .fill(controller.isRunning ? Theme.running : Theme.surfaceRaised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                        .strokeBorder(controller.isRunning ? .clear : Theme.accent.opacity(0.7), lineWidth: 2)
                )
                .contentShape(Rectangle())
        }
        .accessibilityLabel(controller.isRunning ? "Stop metronome" : "Start metronome")
    }

    @ViewBuilder
    private var content: some View {
        if showsLabel {
            // Drop the word rather than wrapping it. A narrow window used to
            // break "START" across three lines, which looked broken and made
            // the glyph tiny.
            ViewThatFits(in: .horizontal) {
                labelled
                glyph(scale: 0.40)
            }
        } else {
            glyph(scale: 0.40)
        }
    }

    private var labelled: some View {
        HStack(spacing: 12) {
            glyph(scale: 0.32)
            Text(title)
                .font(.system(size: height * 0.26, weight: .heavy, design: .rounded))
                .kerning(1.5)
                .lineLimit(1)
                // Without this the text would compress to fit instead of
                // reporting that it does not, and ViewThatFits would never
                // fall through to the glyph.
                .fixedSize()
        }
        .padding(.horizontal, 10)
    }

    private func glyph(scale: CGFloat) -> some View {
        Image(systemName: symbol)
            .font(.system(size: height * scale, weight: .bold))
    }
}
