import SwiftUI
import SelahBeatCore

/// The library as tiles, with an add tile in the last position.
///
/// A song tile leads with its tempo, because that is what a drummer is
/// actually looking for.
public struct SongsGridView: View {
    @Bindable private var model: AppModel
    @State private var query = ""
    @State private var editing: Song?
    @State private var creating: Song?
    @State private var toastMessage: String?

    public init(model: AppModel) {
        self.model = model
    }

    private var songs: [Song] {
        query.trimmingCharacters(in: .whitespaces).isEmpty
            ? model.library.allSongs
            : model.library.search(query)
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                searchField
                LazyVGrid(columns: TileGrid.columns, spacing: TileGrid.spacing) {
                    ForEach(songs) { song in
                        tile(song)
                    }
                    AddTile(title: "New Song") {
                        creating = Song(
                            title: "",
                            defaultBPM: model.metronome.bpm,
                            defaultTimeSignature: model.metronome.timeSignature
                        )
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)

                if songs.isEmpty && !query.isEmpty {
                    Text("No songs match \u{201C}\(query)\u{201D}")
                        .font(.callout)
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.top, 24)
                }
            }
        }
        .background(Theme.surface)
        .toast($toastMessage)
        .navigationTitle("Library")
        .sheet(item: $editing) { song in
            SongEditorView(model: model, song: song) { saved in
                model.library.updateSong(saved)
            }
        }
        .sheet(item: $creating) { song in
            SongEditorView(model: model, song: song, isNew: true) { saved in
                model.library.addSong(saved)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondaryText)
            TextField("Search your songs", text: $query)
                .textFieldStyle(.plain)
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(10)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private func tile(_ song: Song) -> some View {
        let isLoaded = model.metronome.loadedItem?.song.id == song.id

        return Button {
            // Tapping loads the tempo into the transport — the common action.
            // Editing lives in the context menu and the pencil.
            model.metronome.loadSong(song)
        } label: {
            TileCard(isHighlighted: isLoaded) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(Int(song.defaultBPM))")
                            .font(Theme.tempoFont(size: 30))
                            .foregroundStyle(Theme.primaryText)
                        Text("BPM")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.secondaryText)
                        Spacer()
                        if isLoaded {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.running)
                        }
                    }

                    Text(song.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if let artist = song.artist {
                        Text(artist)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 2)

                    HStack(spacing: 5) {
                        TileChip(song.defaultTimeSignature.display)
                        if let key = song.defaultKey {
                            TileChip(key.display, tint: Theme.accent)
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Load into transport") { model.metronome.loadSong(song) }
            AddToServiceMenu(model: model, songID: song.id, key: song.defaultKey) { message in
                toastMessage = message
            }
            Button("Edit\u{2026}") { editing = song }
            // Opens the editor on the copy, since the reason to duplicate is
            // almost always to change something about it.
            Button("Duplicate\u{2026}") {
                if let copy = model.library.duplicateSong(song.id) {
                    editing = copy
                }
            }
            Divider()
            Button("Delete", role: .destructive) { model.library.deleteSong(song.id) }
        }
    }
}
