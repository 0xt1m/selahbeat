import SwiftUI
import SelahBeatCore

/// Narrow-screen transport.
///
/// Only what matters mid-song: start/stop, the tempo, tap, and where you are
/// in the bar. Everything else lives on the Metronome tab, which has room.
public struct CompactTransportBar: View {
    @Bindable private var model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    private var controller: MetronomeController { model.metronome }

    public var body: some View {
        VStack(spacing: 0) {
            if controller.isBluetoothWarningActive {
                Label("Bluetooth adds latency", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(Theme.warning)
            }

            HStack(spacing: 10) {
                if model.canStepBackward {
                    stepButton(systemName: "backward.end.fill", delta: -1)
                }

                StartStopButton(controller: controller, height: 52, showsLabel: false)
                    .frame(minWidth: 96)

                VStack(spacing: -1) {
                    Text("\(Int(controller.bpm))")
                        .font(Theme.tempoFont(size: 24))
                        .foregroundStyle(Theme.primaryText)
                    Text("BPM")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.secondaryText)
                }
                .fixedSize()

                TapPad(controller: controller)

                if model.canStepForward {
                    stepButton(systemName: "forward.end.fill", delta: 1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            BeatDots(controller: controller, dotSize: 10, granularity: .beats)
                .padding(.top, 6)
                .padding(.bottom, 8)

            if let loaded = controller.loadedItem {
                Text(loaded.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .padding(.bottom, 6)
            }
        }
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
        }
    }

    private func stepButton(systemName: String, delta: Int) -> some View {
        Button {
            model.step(delta)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
                .frame(width: 40, height: 40)
                .background(Theme.surfaceRaised, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(delta > 0 ? "Next song" : "Previous song")
    }
}
