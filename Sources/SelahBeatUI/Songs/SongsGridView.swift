import SwiftUI
import SelahBeatCore

/// The library as tiles, with an add tile in the last position.
///
/// A song tile leads with its tempo, because that is what a drummer is
/// actually looking for.
public struct SongsGridView: View {
    @Bindable private var model: AppModel
    @State private var query = ""
    @State private var creating: Song?
    @State private var toastMessage: String?
    @State private var showingSettings = false

    public init(model: AppModel) {
        self.model = model
    }

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    private var songs: [Song] {
        trimmed.isEmpty ? model.library.allSongs : model.library.search(query)
    }

    /// Catalog matches, shown under their own heading while searching. Never
    /// merged with your own songs: yours is what you will play, the server's
    /// is only a suggestion until you add it.
    private var catalogMatches: [CatalogSong] {
        guard !trimmed.isEmpty else { return [] }
        return model.search(query).catalog
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

                if songs.isEmpty && !trimmed.isEmpty {
                    Text("Nothing in your library matches \u{201C}\(query)\u{201D}")
                        .font(.callout)
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                }

                if !catalogMatches.isEmpty {
                    catalogSection
                }
            }
        }
        .background(Theme.surface)
        .toast($toastMessage)
        .navigationTitle("Library")
        .task { await model.refreshCatalogNow() }
        // iPhone has no Settings scene, so this is the way in - and the only
        // place the version number would otherwise be invisible.
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingSettings = true } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView(model: model)
                    .navigationTitle("Settings")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showingSettings = false }
                        }
                    }
            }
        }
        #endif
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
                .keyboardDoneButton()
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

    private var catalogSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "cloud")
                    .font(.system(size: 11, weight: .semibold))
                Text("From the song server")
                    .font(.system(size: 12, weight: .bold))
                Text("tap to add to your library")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
            }
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 18)

            LazyVGrid(columns: TileGrid.columns, spacing: TileGrid.spacing) {
                ForEach(catalogMatches) { entry in
                    catalogTile(entry)
                }
            }
            .padding(.horizontal, 18)
        }
        .padding(.top, 6)
        .padding(.bottom, 20)
    }

    private func catalogTile(_ entry: CatalogSong) -> some View {
        Button {
            let added = model.importCatalogSong(entry)
            model.metronome.loadSong(added)
            toastMessage = "Added \(added.title) to your library"
        } label: {
            TileCard {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(Int(entry.bpm))")
                            .font(Theme.tempoFont(size: 30))
                            .foregroundStyle(Theme.primaryText)
                        Text("BPM")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.secondaryText)
                        Spacer()
                        Image(systemName: "plus.circle")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.accent)
                    }

                    Text(entry.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if let artist = entry.artist {
                        Text(artist)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 2)

                    HStack(spacing: 5) {
                        TileChip("\(entry.beats)/\(entry.noteValue)")
                        if let key = entry.key {
                            TileChip(key, tint: Theme.accent)
                        }
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: Theme.corner)
                    .strokeBorder(Theme.accent.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
        }
        .buttonStyle(.plain)
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
            Button("Edit\u{2026}") { model.editingSong = song }
            // Opens the editor on the copy, since the reason to duplicate is
            // almost always to change something about it.
            Button("Duplicate\u{2026}") {
                if let copy = model.library.duplicateSong(song.id) {
                    model.editingSong = copy
                }
            }
            Divider()
            Button("Delete", role: .destructive) { model.library.deleteSong(song.id) }
        }
    }
}
