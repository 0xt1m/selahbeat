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
        metronome.accentGain = settings.values.accentGain
        metronome.quarterGain = settings.values.quarterGain
        metronome.eighthGain = settings.values.eighthGain
        metronome.sixteenthGain = settings.values.sixteenthGain
        metronome.applyLevelGains()
        metronome.refreshDiagnostics()

        #if DEBUG
        seedSampleDataIfRequested()
        #endif

        if let baseURL = settings.serverBaseURL {
            sync = CatalogSync(service: APIClient(baseURL: baseURL), cache: catalog)
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
        settings.values.accentGain = metronome.accentGain
        settings.values.quarterGain = metronome.quarterGain
        settings.values.eighthGain = metronome.eighthGain
        settings.values.sixteenthGain = metronome.sixteenthGain
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
        public var catalog: [CatalogSong] = []
        /// For catalog entries the user already has, the tempo of their own
        /// copy. Lets the UI explain why the two rows disagree.
        public var localBPMForCatalogID: [String: Double] = [:]

        public var isEmpty: Bool { library.isEmpty && catalog.isEmpty }
    }

    /// Merged, synchronous, offline.
    ///
    /// A song you already have and the catalog's version of it are shown as
    /// separate rows under their own headings. They are genuinely different
    /// things now that the catalog never writes to your library: yours is what
    /// you will play, the catalog's is what the server currently suggests.
    public func search(_ query: String) -> SearchResults {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return SearchResults(library: library.recentSongs, catalog: [])
        }
        let local = library.search(query, limit: 25)
        let remote = catalog.search(query, limit: 25)

        // Provenance now lives in `origin`, since library songs carry their own
        // local identity rather than the catalog slug.
        var localBPM: [String: Double] = [:]
        for song in local {
            if let slug = song.origin.catalogID {
                localBPM[slug] = song.defaultBPM
            }
        }
        return SearchResults(library: local, catalog: remote, localBPMForCatalogID: localBPM)
    }

    /// Adds a catalog entry to the library as a new, independent song.
    ///
    /// Never looks for or modifies an existing copy. Every song in the library
    /// is its own object: adding "Praise" from the catalog when you already
    /// have a "Praise" gives you a second one at the server's tempo, and your
    /// original is untouched.
    @discardableResult
    public func importCatalogSong(_ entry: CatalogSong) -> Song {
        library.addSong(entry.toSong())
    }

    /// Forces a catalog refresh, ignoring the staleness window.
    ///
    /// Called when the add-song sheet opens: that is the moment a stale tempo
    /// actually costs the user something.
    public func refreshCatalogNow() async {
        guard network.isOnline else { return }
        await sync?.sync()
    }

    public var isSyncingCatalog: Bool { sync?.isSyncing ?? false }

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
