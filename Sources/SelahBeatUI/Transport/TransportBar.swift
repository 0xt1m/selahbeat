import SwiftUI
import SelahBeatCore

/// Persistent chrome, not a screen.
///
/// Start/Stop and the tempo stay reachable while the drummer browses the
/// service — the alternative (navigating back to a metronome screen mid-song)
/// is exactly the fumble this app exists to prevent.
///
/// Controls are dropped by priority as the window narrows rather than being
/// allowed to overflow: at any width the bar keeps transport, tempo and tap,
/// and everything else is a bonus that lives elsewhere too.
public struct TransportBar: View {
    @Bindable private var model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    private var controller: MetronomeController { model.metronome }

    // Width at which each optional control earns its place.
    private enum Breakpoint {
        static let beatDots: CGFloat = 700
        static let meter: CGFloat = 800
        static let subdivision: CGFloat = 900
        static let sound: CGFloat = 1000
        static let soundLabel: CGFloat = 1120
        static let loadedSong: CGFloat = 1220
    }

    public var body: some View {
        VStack(spacing: 0) {
            if controller.isBluetoothWarningActive {
                bluetoothWarning
            }
            GeometryReader { proxy in
                content(width: proxy.size.width)
            }
            .frame(height: Theme.transportHeight)
        }
        .background(Theme.surface)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
        }
    }

    private func content(width: CGFloat) -> some View {
        HStack(spacing: 12) {
            stepButton(systemName: "backward.end.fill", enabled: model.canStepBackward, delta: -1)

            StartStopButton(controller: controller, showsLabel: false)
                .frame(width: 96)

            stepButton(systemName: "forward.end.fill", enabled: model.canStepForward, delta: 1)

            Divider().frame(height: 38)

            BPMControl(controller: controller, size: 38)

            TapPad(controller: controller)

            if width >= Breakpoint.meter {
                Divider().frame(height: 38)
                TimeSignaturePicker(controller: controller)
            }
            if width >= Breakpoint.subdivision {
                SubdivisionPicker(controller: controller)
            }
            if width >= Breakpoint.beatDots {
                BeatDots(controller: controller, dotSize: 12, granularity: .beats)
                    .fixedSize()
            }

            Spacer(minLength: 8)

            if width >= Breakpoint.loadedSong, let loaded = controller.loadedItem {
                loadedSongLabel(loaded)
            }
            if width >= Breakpoint.sound {
                SoundPicker(controller: controller, showsLabel: width >= Breakpoint.soundLabel)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxHeight: .infinity)
    }

    private func loadedSongLabel(_ item: ResolvedItem) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(item.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)
            HStack(spacing: 6) {
                if let key = item.key {
                    Text(key.display)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }
                Text(item.timeSignature.display)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(maxWidth: 180, alignment: .trailing)
    }

    private func stepButton(systemName: String, enabled: Bool, delta: Int) -> some View {
        Button {
            model.step(delta)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 40, height: 40)
                .background(Theme.surfaceRaised, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(delta > 0 ? "Next song" : "Previous song")
    }

    /// Bluetooth adds 150-300 ms of codec latency that no amount of engine
    /// tuning removes. Saying so plainly beats letting a drummer discover it
    /// on stage.
    private var bluetoothWarning: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("\(controller.diagnostics.route) adds noticeable latency \u{2014} use wired or in-ear monitors for accurate timing.")
                .font(.system(size: 12, weight: .medium))
            Spacer()
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 18)
        .padding(.vertical, 7)
        .background(Theme.warning)
    }
}
