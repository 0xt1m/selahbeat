import SwiftUI
import SelahBeatCore

/// Where the app is actually used: on a dark stage, glanced at from a metre
/// away, operated without looking. Everything is oversized and nothing
/// destructive is anywhere near the Start button.
public struct StageModeView: View {
    @Bindable private var model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    private var controller: MetronomeController { model.metronome }

    public var body: some View {
        ZStack {
            Theme.stageBackground.ignoresSafeArea()

            VStack(spacing: 26) {
                HStack {
                    Button {
                        model.isStageMode = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Theme.secondaryText)
                            .frame(width: 46, height: 46)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.escape, modifiers: [])
                    Spacer()
                    if controller.isBluetoothWarningActive {
                        Label("Bluetooth latency", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.warning)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                Spacer()

                if let loaded = controller.loadedItem {
                    VStack(spacing: 8) {
                        Text(loaded.title)
                            .font(.system(size: 46, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.primaryText)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.5)
                            .lineLimit(2)
                        if let key = loaded.key {
                            Text(key.display)
                                .font(.system(size: 30, weight: .semibold, design: .rounded))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    .padding(.horizontal, 30)
                }

                Text(String(Int(controller.bpm)))
                    .font(Theme.tempoFont(size: 190))
                    .foregroundStyle(Theme.primaryText)
                    .contentTransition(.numericText())

                HStack(spacing: 14) {
                    Text(controller.timeSignature.display)
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.secondaryText)
                    BeatDots(controller: controller, dotSize: 26)
                }

                Spacer()

                HStack(spacing: 18) {
                    stageStep(systemName: "backward.end.fill", enabled: model.canStepBackward, delta: -1)
                    StartStopButton(controller: controller, height: 118)
                    stageStep(systemName: "forward.end.fill", enabled: model.canStepForward, delta: 1)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
        }
    }

    private func stageStep(systemName: String, enabled: Bool, delta: Int) -> some View {
        Button {
            model.step(delta)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
                .frame(width: 92, height: 118)
                .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.corner))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
    }
}
