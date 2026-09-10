import SwiftUI
import SelahBeatCore

/// A set list. Rows are draggable, tappable to load into the transport, and
/// carry the key the team is playing this week.
public struct ServiceDetailView: View {
    @Bindable private var model: AppModel
    private let serviceID: UUID

    @State private var showingAddSong = false
    @State private var editingItemID: UUID?
    @State private var renaming = false
    @State private var draftName = ""
    @State private var toastMessage: String?

    public init(model: AppModel, serviceID: UUID) {
        self.model = model
        self.serviceID = serviceID
    }

    private var service: Service? { model.library.service(serviceID) }
    private var items: [ResolvedItem] { model.library.resolvedItems(in: serviceID) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if items.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .background(Theme.surface)
        .toast($toastMessage)
        .sheet(isPresented: $showingAddSong) {
            AddSongSheet(model: model, serviceID: serviceID)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if renaming {
                    TextField("Service name", text: $draftName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .onSubmit(commitRename)
                } else {
                    Text(service?.name ?? "Service")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.primaryText)
                        .onTapGesture(count: 2) {
                            draftName = service?.name ?? ""
                            renaming = true
                        }
                }
                Spacer()
                Button {
                    showingAddSong = true
                } label: {
                    Label("Add Song", systemImage: "plus")
                }
                .keyboardShortcut("k", modifiers: .command)
            }

            HStack(spacing: 10) {
                if let date = service?.date {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                }
                Text("\(items.count) song\(items.count == 1 ? "" : "s")")
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.secondaryText)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private var list: some View {
        List {
            ForEach(items) { resolved in
                ServiceRow(
                    model: model,
                    serviceID: serviceID,
                    resolved: resolved,
                    isLoaded: model.metronome.loadedItem?.item.id == resolved.item.id,
                    isEditing: editingItemID == resolved.item.id,
                    toggleEditing: {
                        editingItemID = editingItemID == resolved.item.id ? nil : resolved.item.id
                    },
                    onToast: { toastMessage = $0 }
                )
                .listRowBackground(Color.clear)
                .listRowSeparatorTint(Color.white.opacity(0.08))
            }
            .onMove { offsets, destination in
                model.library.moveItems(in: serviceID, from: offsets, to: destination)
            }
            .onDelete { offsets in
                for index in offsets where items.indices.contains(index) {
                    model.library.removeItem(items[index].item.id, from: serviceID)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "music.note.list")
                .font(.system(size: 40))
                .foregroundStyle(Theme.secondaryText)
            Text("No songs yet")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
            Text("Add a song to build this week's set. Songs you add are saved for next time.")
                .font(.callout)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
            Button("Add Song") { showingAddSong = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func commitRename() {
        guard var service else { return }
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            service.name = trimmed
            model.library.updateService(service)
        }
        renaming = false
    }
}

/// One row in a set list.
struct ServiceRow: View {
    @Bindable var model: AppModel
    let serviceID: UUID
    let resolved: ResolvedItem
    let isLoaded: Bool
    let isEditing: Bool
    let toggleEditing: () -> Void
    let onToast: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(Theme.secondaryText.opacity(0.6))
                    .font(.system(size: 13))

                VStack(alignment: .leading, spacing: 2) {
                    Text(resolved.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isLoaded ? Theme.accent : Theme.primaryText)
                    if let artist = resolved.song.artist {
                        Text(artist)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.secondaryText)
                    }
                }

                Spacer()

                if let key = resolved.key {
                    Text(key.display)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .frame(minWidth: 34)
                }

                HStack(spacing: 3) {
                    Text("\(Int(resolved.bpm))")
                        .font(Theme.tempoFont(size: 17))
                    if resolved.hasBPMOverride {
                        Image(systemName: "pencil")
                            .font(.system(size: 8))
                            .foregroundStyle(Theme.accent)
                    }
                }
                .foregroundStyle(Theme.primaryText)

                Text(resolved.timeSignature.display)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(minWidth: 30)

                Button {
                    model.metronome.load(resolved, serviceID: serviceID)
                } label: {
                    Image(systemName: isLoaded ? "checkmark.circle.fill" : "arrow.up.circle")
                        .font(.system(size: 18))
                        .foregroundStyle(isLoaded ? Theme.running : Theme.secondaryText)
                }
                .buttonStyle(.plain)
                .help("Load this song's tempo into the transport")

                Button {
                    toggleEditing()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.secondaryText)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                model.metronome.load(resolved, serviceID: serviceID)
            }

            if isEditing {
                ServiceItemEditor(model: model, serviceID: serviceID, resolved: resolved)
                    .padding(.bottom, 10)
            }
        }
        .contextMenu {
            Button("Load into transport") { model.metronome.load(resolved, serviceID: serviceID) }
            AddToServiceMenu(
                model: model,
                songID: resolved.song.id,
                key: resolved.key,
                excluding: serviceID,
                onAdded: onToast
            )
            Button("Edit song\u{2026}") { toggleEditing() }
            Divider()
            Button("Remove from service", role: .destructive) {
                model.library.removeItem(resolved.item.id, from: serviceID)
            }
        }
    }
}

/// Per-placement overrides. Key and tempo here belong to *this week's*
/// arrangement, not to the song itself.
struct ServiceItemEditor: View {
    @Bindable var model: AppModel
    let serviceID: UUID
    let resolved: ResolvedItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                keyPicker
                bpmOverride
                Spacer()
            }
            TextField("Notes (e.g. half-time feel at bridge)", text: notesBinding, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
        .padding(.leading, 26)
    }

    private var keyPicker: some View {
        HStack(spacing: 6) {
            Text("Key").font(.caption).foregroundStyle(Theme.secondaryText)
            Menu {
                Button("None") { update { $0.key = nil } }
                Divider()
                ForEach(MusicalKey.common) { key in
                    Button(key.display) { update { $0.key = key } }
                }
            } label: {
                Text(resolved.item.key?.display ?? resolved.song.defaultKey?.display ?? "\u{2014}")
                    .frame(minWidth: 44)
            }
            .fixedSize()
        }
    }

    private var bpmOverride: some View {
        HStack(spacing: 6) {
            Text("Tempo").font(.caption).foregroundStyle(Theme.secondaryText)
            TextField(
                "\(Int(resolved.song.defaultBPM))",
                value: Binding(
                    get: { resolved.item.bpmOverride },
                    set: { newValue in update { $0.bpmOverride = newValue.map(Song.clampBPM) } }
                ),
                format: .number
            )
            .frame(width: 56)
            .textFieldStyle(.roundedBorder)

            if resolved.hasBPMOverride {
                Button {
                    update { $0.bpmOverride = nil }
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.plain)
                .help("Revert to the song's tempo (\(Int(resolved.song.defaultBPM)))")
            }
        }
    }

    private var notesBinding: Binding<String> {
        Binding(
            get: { resolved.item.notes ?? "" },
            set: { newValue in
                update { $0.notes = newValue.isEmpty ? nil : newValue }
            }
        )
    }

    private func update(_ mutate: (inout ServiceItem) -> Void) {
        var item = resolved.item
        mutate(&item)
        model.library.updateItem(item, in: serviceID)
        // Keep the transport in step if this is the loaded song.
        if model.metronome.loadedItem?.item.id == item.id,
           let refreshed = model.library.resolved(item) {
            model.metronome.load(refreshed, serviceID: serviceID)
        }
    }
}
