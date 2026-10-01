import SwiftUI
import SelahBeatCore

/// Where each sound goes on a multi-output interface.
///
/// The common setup on stage is click to the drummer's output and pad to
/// another, which is why these are separate rows rather than one master
/// output setting.
public struct OutputRoutingView: View {
    @Bindable private var model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    private var channelCount: Int { max(1, model.metronome.outputChannelCount) }

    public var body: some View {
        Form {
            Section {
                HStack {
                    Text("Outputs available")
                    Spacer()
                    Text("\(channelCount)").foregroundStyle(.secondary)
                }
                Text(channelCount > 2
                     ? "Send the click and the pad to different outputs of your interface."
                     : "With two outputs, the click and the pad can be split left and right \u{2014} the usual way to feed a drummer's in-ear.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Audio interface")
            }

            channelSection("Click", selection: Bindable(model.metronome).clickChannels)
            channelSection("Pad", selection: Bindable(model.metronome).padChannels)

            Section {
                Button("Send everything everywhere") {
                    model.metronome.clickChannels = []
                    model.metronome.padChannels = []
                }
                .disabled(model.metronome.clickChannels.isEmpty && model.metronome.padChannels.isEmpty)
            } footer: {
                Text("With nothing selected a sound plays on every output, which is what built-in speakers and headphones want.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onDisappear { model.persistSettingsFromMetronome() }
    }

    private func channelSection(_ title: String, selection: Binding<Set<Int>>) -> some View {
        Section(title) {
            // Wraps rather than scrolling: an 18i20's 20 outputs still have to
            // fit on a phone.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 62), spacing: 8)], spacing: 8) {
                ForEach(1...channelCount, id: \.self) { channel in
                    let isOn = selection.wrappedValue.contains(channel)
                    Button {
                        var updated = selection.wrappedValue
                        if isOn { updated.remove(channel) } else { updated.insert(channel) }
                        selection.wrappedValue = updated
                    } label: {
                        Text(label(for: channel))
                            .font(.system(size: 12, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(isOn ? Theme.accent.opacity(0.25) : Theme.surfaceRaised,
                                        in: RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(isOn ? Theme.accent : Color.clear, lineWidth: 1)
                            )
                            .foregroundStyle(isOn ? Theme.accent : Theme.secondaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)

            if selection.wrappedValue.isEmpty {
                Text("Every output").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// Two outputs are left and right; more than that, people think in numbers.
    private func label(for channel: Int) -> String {
        guard channelCount == 2 else { return "\(channel)" }
        return channel == 1 ? "L" : "R"
    }
}
