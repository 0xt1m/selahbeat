import SwiftUI
import SelahBeatCore

/// Offers to keep the tempo currently in the transport as the loaded song's
/// tempo.
///
/// Appears only when the two differ, and never saves on its own: a tempo
/// tapped in to match the band this once should not quietly rewrite the song.
///
/// It owns all three states rather than letting the caller switch on them,
/// because saving makes the tempos match - so a caller-side condition would
/// tear the view down before the confirmation could be seen.
public struct SaveTempoButton: View {
    @Bindable private var model: AppModel
    private let showsTitleWhenIdle: Bool
    @State private var justSaved = false

    public init(model: AppModel, showsTitleWhenIdle: Bool = false) {
        self.model = model
        self.showsTitleWhenIdle = showsTitleWhenIdle
    }

    private var title: String { model.metronome.loadedItem?.title ?? "" }

    public var body: some View {
        Group {
            if justSaved {
                pill(icon: "checkmark", text: "Saved to \(title)", tint: Theme.running)
            } else if model.loadedSongTempoDiffers {
                Button {
                    model.saveTempoToLoadedSong()
                    justSaved = true
                } label: {
                    pill(icon: "square.and.arrow.down",
                         text: "Save \(Int(model.metronome.bpm)) BPM to \(title)",
                         tint: Theme.accent)
                }
                .buttonStyle(.plain)
                .help("Make this the song's tempo")
            } else if showsTitleWhenIdle {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
        }
        .task(id: justSaved) {
            guard justSaved else { return }
            try? await Task.sleep(for: .seconds(1.4))
            justSaved = false
        }
        .animation(.easeOut(duration: 0.15), value: justSaved)
    }

    private func pill(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(tint.opacity(0.15)))
        .contentShape(Capsule())
    }
}
