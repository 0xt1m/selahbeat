import SwiftUI
import SelahBeatCore

/// Search and add.
///
/// Local and cached-catalog results are computed synchronously on every
/// keystroke — no debounce, no spinner, no network — because both live in
/// memory. Typing a name that matches nothing offers to create it on the spot,
/// which is the fastest path for a song the catalog has never heard of.
public struct AddSongSheet: View {
    @Bindable private var model: AppModel
    private let serviceID: UUID?

    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""
    @State private var creating: Song?
    @FocusState private var searchFocused: Bool

    public init(model: AppModel, serviceID: UUID? = nil) {
        self.model = model
        self.serviceID = serviceID
    }

    private var results: AppModel.SearchResults { model.search(query) }
    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    public var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            content
            Divider()
            footer
        }
        .sheetSize(width: 520, height: 460)
        .background(Theme.surface)
        .sheet(item: $creating) { song in
            SongEditorView(model: model, song: song, isNew: true) { saved in
                add(saved)
            }
        }
        .onAppear { searchFocused = true }
        // Refresh on open rather than waiting for the background window: this
        // is the moment a corrected tempo actually matters.
        .task { await model.refreshCatalogNow() }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondaryText)
            TextField("Search songs by title or artist", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .focused($searchFocused)
                .onSubmit(addFirstResultOrCreate)
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if trimmed.isEmpty && !results.library.isEmpty {
                    sectionHeader("Recent")
                }

                if !results.library.isEmpty {
                    if !trimmed.isEmpty { sectionHeader("Your library") }
                    ForEach(results.library) { song in
                        resultRow(
                            title: song.title,
                            artist: song.artist,
                            bpm: song.defaultBPM,
                            signature: song.defaultTimeSignature,
                            key: song.defaultKey,
                            badge: song.origin.isCatalog ? nil : "custom",
                            note: nil
                        ) {
                            add(song)
                        }
                    }
                }

                if !results.catalog.isEmpty {
                    sectionHeader("SelahBeat catalog")
                    ForEach(results.catalog) { entry in
                        resultRow(
                            title: entry.title,
                            artist: entry.artist,
                            bpm: entry.bpm,
                            signature: entry.timeSignature,
                            key: entry.musicalKey,
                            badge: nil,
                            note: yoursNote(for: entry)
                        ) {
                            add(model.importCatalogSong(entry))
                        }
                    }
                }

                if !trimmed.isEmpty {
                    createRow
                }

                if results.isEmpty && trimmed.isEmpty {
                    Text("Start typing to find a song, or create your own.")
                        .font(.callout)
                        .foregroundStyle(Theme.secondaryText)
                        .padding(24)
                }
            }
        }
    }

    /// Always offered, even when there are matches — the catalog's "Goodness Of
    /// God" is not necessarily the arrangement this team plays.
    private var createRow: some View {
        Button {
            creating = Song(
                title: trimmed,
                defaultBPM: model.metronome.bpm,
                defaultTimeSignature: model.metronome.timeSignature
            )
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Create \u{201C}\(trimmed)\u{201D}")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                    Text("Set your own tempo, meter and key")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Says plainly what tapping this row will do when a copy already exists,
    /// so replacing a saved tempo is never a surprise.
    private func yoursNote(for entry: CatalogSong) -> String? {
        guard let mine = results.localBPMForCatalogID[entry.id] else { return nil }
        if Int(mine) == Int(entry.bpm) {
            return "You already have a copy \u{2014} this adds another"
        }
        return "You have a copy at \(Int(mine)) BPM \u{2014} this adds another"
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .kerning(1)
            .foregroundStyle(Theme.secondaryText)
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 4)
    }

    private func resultRow(
        title: String,
        artist: String?,
        bpm: Double,
        signature: TimeSignature,
        key: MusicalKey?,
        badge: String?,
        note: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.primaryText)
                        if let badge {
                            Text(badge)
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Theme.accentDim, in: Capsule())
                                .foregroundStyle(Theme.primaryText)
                        }
                    }
                    if let artist {
                        Text(artist).font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                    }
                    if let note {
                        Text(note)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.accent.opacity(0.9))
                    }
                }
                Spacer()
                if let key {
                    Text(key.display)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }
                Text(signature.display)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                Text("\(Int(bpm))")
                    .font(Theme.tempoFont(size: 16))
                    .foregroundStyle(Theme.primaryText)
                    .frame(minWidth: 36, alignment: .trailing)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if !model.network.isOnline {
                Label("Offline \u{2014} showing saved songs", systemImage: "wifi.slash")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            } else if model.isSyncingCatalog {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Updating catalog\u{2026}")
                }
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
            } else {
                Text("\(model.catalog.count) songs in catalog")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                Button {
                    Task { await model.refreshCatalogNow() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .help("Check the server for updated tempos")
            }
            Spacer()
            Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
        }
        .padding(14)
    }

    private func addFirstResultOrCreate() {
        if let first = results.library.first {
            add(first)
        } else if let entry = results.catalog.first {
            add(model.importCatalogSong(entry))
        } else if !trimmed.isEmpty {
            creating = Song(
                title: trimmed,
                defaultBPM: model.metronome.bpm,
                defaultTimeSignature: model.metronome.timeSignature
            )
        }
    }

    private func add(_ song: Song) {
        if model.library.song(song.id) == nil {
            model.library.addSong(song)
        }
        if let serviceID {
            model.library.addSong(song.id, to: serviceID, key: song.defaultKey)
        } else {
            model.library.noteUse(song.id)
        }
        query = ""
        searchFocused = true
        if serviceID != nil { dismiss() }
    }
}
