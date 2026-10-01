import SwiftUI
import SelahBeatCore

/// Pad controls where you would actually reach for them.
///
/// A pad is a performance control, not a preference: you turn it on between
/// songs, change its key when the band does, and pull it down when someone
/// starts speaking. All of that belongs on the screen you are already looking
/// at, not three tabs into Settings.
public struct PadCard: View {
    @Bindable private var model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    private var controller: MetronomeController { model.metronome }

    /// Offers to make a change permanent rather than making it permanent
    /// silently: a pad switched off for one Sunday is not the same as a song
    /// that should never have one.
    private func saveRow(_ change: AppModel.PadChange) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 10, weight: .bold))
            Text(summary(change))
                .font(.system(size: 11, weight: .medium))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            Button("Save") { model.savePadToLoadedSong() }
                .font(.system(size: 11, weight: .semibold))
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
        }
        .foregroundStyle(Theme.secondaryText)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private func summary(_ change: AppModel.PadChange) -> String {
        let padPart = change.enablesPad ? "pad on" : "pad off"
        let keyPart = change.changesKey ? " in \(change.key.display)" : ""
        let soundPart = change.changesSound ? " (\(change.sound.name))" : ""
        return "Save \(padPart)\(keyPart)\(soundPart) for \(change.title)?"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Pad")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.primaryText)

                Spacer()

                // Follows what you can hear, not what is configured: a song
                // starting its own pad switches this on, and stopping the click
                // switches it back off.
                Toggle("", isOn: Binding(
                    get: { controller.isPadSounding },
                    set: { controller.setPadSounding($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }

            // Says what will happen rather than what is configured: a drummer
            // reading this mid-service has one question, and it is "will a pad
            // play when I hit start".
            if controller.loadedSongPlaysPad, !controller.padManualOn,
               controller.padSuppressedSongID != controller.loadedItem?.song.id {
                Label("Starts with the click for this song", systemImage: "music.note")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.accent)
            }

            if let change = model.pendingPadChange {
                saveRow(change)
            }

            HStack(spacing: 10) {
                Text("Key").font(.system(size: 12)).foregroundStyle(Theme.secondaryText)

                Menu {
                    ForEach(MusicalKey.common) { key in
                        Button(key.display) { controller.setPadKeyManually(key) }
                    }
                    if !controller.padFollowsSong {
                        Divider()
                        Button("Follow the song") { controller.resumePadFollowingSong() }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(controller.padKey.display)
                            .font(.system(size: 14, weight: .bold))
                        if controller.padFollowsSong {
                            Image(systemName: "link")
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                }
                .fixedSize()

                Menu {
                    ForEach(PadSound.allCases) { sound in
                        Button {
                            controller.setPadSoundManually(sound)
                        } label: {
                            // The description is what makes these choosable
                            // without auditioning all five mid-service.
                            Text("\(sound.name) \u{2014} \(sound.detail)")
                        }
                    }
                } label: {
                    Text(controller.padSound.name)
                        .font(.system(size: 13, weight: .medium))
                }
                .fixedSize()

                Spacer()

                Image(systemName: "speaker.wave.2")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                Slider(value: Bindable(controller).padLevel, in: 0...1.5)
                    .frame(maxWidth: 160)
                    .tint(Theme.accent)
            }
        }
        .padding(14)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.corner))
    }
}
