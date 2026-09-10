import SwiftUI
import SelahBeatCore

/// "Add to Service" submenu, shared by every place a song can be right-clicked.
///
/// Adding always carries the song's key across as the starting point for that
/// placement — the team can change it per service afterwards.
public struct AddToServiceMenu: View {
    @Bindable private var model: AppModel
    private let songID: SongID
    private let key: MusicalKey?
    private let excluding: UUID?
    private let onAdded: (String) -> Void

    public init(
        model: AppModel,
        songID: SongID,
        key: MusicalKey? = nil,
        excluding: UUID? = nil,
        onAdded: @escaping (String) -> Void = { _ in }
    ) {
        self.model = model
        self.songID = songID
        self.key = key
        self.excluding = excluding
        self.onAdded = onAdded
    }

    private var services: [Service] {
        model.library.sortedServices.filter { $0.id != excluding }
    }

    public var body: some View {
        Menu("Add to Service") {
            ForEach(services) { service in
                Button {
                    model.library.addSong(songID, to: service.id, key: key)
                    onAdded("Added to \(service.name)")
                } label: {
                    // The count disambiguates similarly-named services.
                    Text("\(service.name) (\(service.items.count))")
                }
            }

            if !services.isEmpty {
                Divider()
            }

            Button("New Service\u{2026}") {
                let service = model.library.createService(name: model.library.suggestedServiceName())
                model.library.addSong(songID, to: service.id, key: key)
                onAdded("Added to \(service.name)")
            }
        }
    }
}
