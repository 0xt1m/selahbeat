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

    public var body: some View {
        InstantButton {
            controller.toggle()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: controller.isRunning ? "stop.fill" : "play.fill")
                    .font(.system(size: height * (showsLabel ? 0.32 : 0.40), weight: .bold))
                if showsLabel {
                    Text(controller.isRunning ? "STOP" : "START")
                        .font(.system(size: height * 0.26, weight: .heavy, design: .rounded))
                        .kerning(1.5)
                }
            }
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
}
