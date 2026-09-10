import Foundation
import Observation
import OSLog

/// Composition root. Everything the UI needs, wired together and bootstrapped.
@MainActor
@Observable
public final class AppModel {
    public let metronome: MetronomeController
    public let library: LibraryStore
    public let catalog: CatalogCache
    public let network: NetworkMonitor
    public let settings: AppSettings
    public let updates = UpdateChecker()
    public private(set) var sync: CatalogSync?

    /// Which service the sidebar has selected, if any.
    public var selectedServiceID: UUID?
    public var isStageMode: Bool = false

    private let log = Logger(subsystem: "app.selahbeat", category: "app")

    public init(
        metronome: MetronomeController,
        library: LibraryStore = LibraryStore(),
        catalog: CatalogCache = CatalogCache(),
        settings: AppSettings = AppSettings()
    ) {
        self.metronome = metronome
        self.library = library
        self.catalog = catalog
        self.settings = settings
        self.network = NetworkMonitor()
    }

    public static func live() -> AppModel {
        AppModel(metronome: .live())
    }

    /// Loads local data. Deliberately does no networking — the app must reach
    /// first frame with zero network involvement.
    public func bootstrap() async {
        await library.bootstrap()
        catalog.bootstrap()

        metronome.timbre = settings.values.timbre
        metronome.subdivision = settings.values.subdivision
        metronome.masterGain = settings.values.masterGain
        metronome.refreshDiagnostics()

        #if DEBUG
        seedSampleDataIfRequested()
        #endif

        if let baseURL = settings.serverBaseURL {
            sync = CatalogSync(
                service: APIClient(baseURL: baseURL),
                cache: catalog,
                library: library
            )
        }
    }

    /// Fired after first render, never during launch. Both the catalog sync
    /// and the update check are deliberately delayed so neither competes with
    /// getting the transport on screen.
    public func startBackgroundSync() {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self else { return }
            await self.updates.check()
            await self.sync?.syncIfStale()
        }
    }

    public func persistSettingsFromMetronome() {
        settings.values.timbre = metronome.timbre
        settings.values.subdivision = metronome.subdivision
        settings.values.masterGain = metronome.masterGain
    }

    public func flush() async {
        persistSettingsFromMetronome()
        await library.flush()
    }

    #if DEBUG
    /// Debug-only fixtures, used for UI screenshots and manual testing.
    /// Triggered by the `-seed-sample-data` launch argument; never runs in a
    /// release build and never touches a library that already has songs.
    public func seedSampleDataIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-seed-sample-data") else { return }
        guard library.allSongs.isEmpty, library.services.isEmpty else { return }

        let picks = ["way-maker", "goodness-of-god", "what-a-beautiful-name",
                     "king-of-kings", "build-my-life", "the-blessing"]
        var songIDs: [SongID] = []
        for slug in picks {
            guard let entry = catalog.song(slug: slug) else { continue }
            songIDs.append(importCatalogSong(entry).id)
        }

        let sunday = library.createService(name: "Sunday Morning")
        for id in songIDs.prefix(4) {
            library.addSong(id, to: sunday.id, key: library.song(id)?.defaultKey)
        }
        let youth = library.createService(name: "Youth Night")
        for id in songIDs.suffix(2) {
            library.addSong(id, to: youth.id, key: library.song(id)?.defaultKey)
        }
    }
    #endif

    // MARK: - Search across library + catalog

    public struct SearchResults: Sendable {
        public var library: [Song] = []
        /// Catalog entries the user has not already imported.
        public var catalog: [CatalogSong] = []
        public var isEmpty: Bool { library.isEmpty && catalog.isEmpty }
    }

    /// Merged, synchronous, offline. Catalog rows the user already owns are
    /// dropped so the same song never appears twice.
    public func search(_ query: String) -> SearchResults {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return SearchResults(library: library.recentSongs, catalog: [])
        }
        let local = library.search(query, limit: 25)
        let owned = Set(local.map(\.id))
        let remote = catalog.search(query, limit: 25).filter { !owned.contains($0.songID) }
        return SearchResults(library: local, catalog: remote)
    }

    /// Imports a catalog song into the library so it works offline forever after.
    @discardableResult
    public func importCatalogSong(_ entry: CatalogSong) -> Song {
        if let existing = library.song(entry.songID) { return existing }
        return library.addSong(entry.toSong())
    }

    // MARK: - Service navigation

    public var selectedService: Service? {
        selectedServiceID.flatMap { library.service($0) }
    }

    public var currentServiceItems: [ResolvedItem] {
        selectedServiceID.map { library.resolvedItems(in: $0) } ?? []
    }

    /// Steps to the next/previous song in the loaded service, loading it into
    /// the transport without starting playback.
    public func step(_ direction: Int) {
        guard let serviceID = metronome.loadedServiceID ?? selectedServiceID else { return }
        let items = library.resolvedItems(in: serviceID)
        guard !items.isEmpty else { return }

        guard let currentID = metronome.loadedItem?.item.id,
              let index = items.firstIndex(where: { $0.item.id == currentID }) else {
            metronome.load(items[0], serviceID: serviceID)
            return
        }

        let next = index + direction
        guard items.indices.contains(next) else { return }
        metronome.load(items[next], serviceID: serviceID)
    }

    public var canStepForward: Bool {
        guard let serviceID = metronome.loadedServiceID else { return false }
        let items = library.resolvedItems(in: serviceID)
        guard let currentID = metronome.loadedItem?.item.id,
              let index = items.firstIndex(where: { $0.item.id == currentID }) else { return !items.isEmpty }
        return items.indices.contains(index + 1)
    }

    public var canStepBackward: Bool {
        guard let serviceID = metronome.loadedServiceID else { return false }
        let items = library.resolvedItems(in: serviceID)
        guard let currentID = metronome.loadedItem?.item.id,
              let index = items.firstIndex(where: { $0.item.id == currentID }) else { return false }
        return items.indices.contains(index - 1)
    }
}
