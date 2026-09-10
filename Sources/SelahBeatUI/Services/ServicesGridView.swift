import SwiftUI
import SelahBeatCore

/// Services as tiles, with an add tile in the last position.
public struct ServicesGridView: View {
    @Bindable private var model: AppModel
    private let onOpen: (UUID) -> Void

    @State private var renamingID: UUID?
    @State private var draftName = ""

    public init(model: AppModel, onOpen: @escaping (UUID) -> Void) {
        self.model = model
        self.onOpen = onOpen
    }

    public var body: some View {
        ScrollView {
            LazyVGrid(columns: TileGrid.columns, spacing: TileGrid.spacing) {
                ForEach(model.library.sortedServices) { service in
                    tile(service)
                }
                AddTile(title: "New Service") {
                    let service = model.library.createService(name: model.library.suggestedServiceName())
                    draftName = service.name
                    renamingID = service.id
                }
            }
            .padding(18)
        }
        .background(Theme.surface)
        .navigationTitle("Services")
        .sheet(item: renameBinding) { service in
            RenameSheet(name: $draftName, title: "Service name") {
                var updated = service
                let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    updated.name = trimmed
                    model.library.updateService(updated)
                }
                renamingID = nil
                onOpen(service.id)
            } onCancel: {
                renamingID = nil
            }
        }
    }

    private var renameBinding: Binding<Service?> {
        Binding(
            get: { renamingID.flatMap { model.library.service($0) } },
            set: { if $0 == nil { renamingID = nil } }
        )
    }

    private func tile(_ service: Service) -> some View {
        let items = model.library.resolvedItems(in: service.id)
        let isLoaded = model.metronome.loadedServiceID == service.id

        return Button {
            onOpen(service.id)
        } label: {
            TileCard(isHighlighted: isLoaded) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "list.bullet.rectangle.portrait")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.accent)
                        Spacer()
                        Text("\(items.count)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.secondaryText)
                    }

                    Text(service.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if let date = service.date {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.secondaryText)
                    }

                    Spacer(minLength: 2)

                    // A glance at the first couple of songs is what tells you
                    // which service this is, faster than the name does.
                    if items.isEmpty {
                        Text("No songs yet")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.secondaryText.opacity(0.7))
                    } else {
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(items.prefix(2)) { item in
                                Text(item.title)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.secondaryText)
                                    .lineLimit(1)
                            }
                            if items.count > 2 {
                                Text("+\(items.count - 2) more")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.secondaryText.opacity(0.7))
                            }
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Open") { onOpen(service.id) }
            Button("Rename") {
                draftName = service.name
                renamingID = service.id
            }
            Button("Duplicate") {
                _ = model.library.duplicateService(service.id, newName: "\(service.name) copy")
            }
            Divider()
            Button("Delete", role: .destructive) {
                model.library.deleteService(service.id)
            }
        }
    }
}

/// Small shared naming sheet — used right after creating a tile, so a new
/// service never sits there called "New Service".
struct RenameSheet: View {
    @Binding var name: String
    let title: String
    let onSave: () -> Void
    let onCancel: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(onSave)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .sheetSize(width: 340, height: 160)
        .presentationDetents([.height(190)])
        .onAppear { focused = true }
    }
}
