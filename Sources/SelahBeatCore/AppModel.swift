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
    /// Set by the macOS app to Sparkle. Nil on iOS, where the App Store owns
    /// updating and the app must not try to update itself.
    public var updater: AppUpdating?
    public private(set) var sync: CatalogSync?
    /// Backup to an anonymous account, and services shared by code. Both are
    /// nil until a server is configured; the app works without either.
    public let syncIdentity = SyncIdentity()
    public private(set) var backup: BackupService?
    public private(set) var shares: ShareService?

    /// Which service the sidebar has selected, if any.
    public var selectedServiceID: UUID?
    /// The song an editor sheet is open on. Lives here rather than in a view
    /// so a keyboard shortcut can open it from anywhere in the app.
    public var editingSong: Song?
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
        metronome.padLevel = settings.values.padLevel
        metronome.padSound = settings.values.padSound
        metronome.clickChannels = settings.values.clickChannels
        metronome.padChannels = settings.values.padChannels

        metronome.refreshDiagnostics()

        #if DEBUG
        seedSampleDataIfRequested()
        #endif

        if let baseURL = settings.serverBaseURL {
            sync = CatalogSync(service: APIClient(baseURL: baseURL), cache: catalog)

            let client = SyncClient(baseURL: baseURL)
            backup = BackupService(identity: syncIdentity, client: client, library: library)
            shares = ShareService(identity: syncIdentity, client: client, library: library)
        }
    }

    /// Fired after first render, never during launch. Both the catalog sync
    /// and the update check are deliberately delayed so neither competes with
    /// getting the transport on screen.
    public func startBackgroundSync() {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self else { return }
            // iOS updates through the App Store. Checking GitHub there would
            // advertise the macOS release, which an iPhone cannot install.
            #if os(macOS)
            await self.updates.check()
            #endif
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
        settings.values.padLevel = metronome.padLevel
        settings.values.padSound = metronome.padSound
        settings.values.clickChannels = metronome.clickChannels
        settings.values.padChannels = metronome.padChannels
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

    // MARK: - Keeping a tapped tempo

    /// The transport is playing the loaded song at a different tempo than the
    /// song itself says - usually because it was just tapped in. Worth
    /// offering to keep, never worth saving silently.
    public var loadedSongTempoDiffers: Bool {
        guard let loaded = metronome.loadedItem else { return false }
        return Int(metronome.bpm.rounded()) != Int(loaded.bpm.rounded())
    }

    /// Writes the transport's tempo onto the loaded song.
    ///
    /// Any per-service tempo override on this placement is cleared: it would
    /// otherwise keep winning, and the set list would still show the old
    /// number right after you pressed Save.
    public func saveTempoToLoadedSong() {
        guard let loaded = metronome.loadedItem else { return }

        var song = loaded.song
        song.defaultBPM = Song.clampBPM(metronome.bpm.rounded())
        library.updateSong(song)

        var item = loaded.item
        if item.bpmOverride != nil, let serviceID = metronome.loadedServiceID {
            item.bpmOverride = nil
            library.updateItem(item, in: serviceID)
        }

        if let refreshed = library.resolved(item) {
            metronome.load(refreshed, serviceID: metronome.loadedServiceID)
        }
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

    /// After a song is edited, puts the new version into the transport if it
    /// is the one loaded - otherwise the click would keep the old tempo until
    /// the song was picked again.
    public func reloadTransportAfterEditing(_ saved: Song) {
        guard metronome.loadedItem?.song.id == saved.id else { return }
        let item = metronome.loadedItem?.item ?? ServiceItem(songID: saved.id)
        if let refreshed = library.resolved(item) {
            metronome.load(refreshed, serviceID: metronome.loadedServiceID)
        }
    }

    /// Opens the editor on whatever song is loaded in the transport - which
    /// is the song you just clicked.
    @discardableResult
    public func editLoadedSong() -> Bool {
        guard let song = metronome.loadedItem?.song else { return false }
        editingSong = song
        return true
    }

    // MARK: - Backup and sharing

    /// The token every sync call needs, registering the device on first use.
    public func syncToken() async throws -> String {
        guard let backup else { throw SyncClient.Failure.offline }
        return try await backup.registerIfNeeded().token
    }

    /// Shares a service and returns the code to hand out.
    public func shareService(_ serviceID: UUID) async throws -> String {
        guard let shares else { throw SyncClient.Failure.offline }
        return try await shares.share(serviceId: serviceID, token: try await syncToken())
    }

    /// Joins a service someone else shared. Returns it, so the UI can open it.
    @discardableResult
    public func joinService(code: String) async throws -> Service {
        guard let shares else { throw SyncClient.Failure.offline }
        return try await shares.join(code: code, token: try await syncToken())
    }

    /// Sends local edits of a shared service up, and pulls anyone else's down.
    public func syncShare(_ serviceID: UUID) async {
        guard let shares, shares.membership(forService: serviceID) != nil else { return }
        do {
            let token = try await syncToken()
            try await shares.push(serviceId: serviceID, token: token)
            _ = try await shares.refresh(serviceId: serviceID, token: token)
        } catch {
            // Sharing is an enrichment; a service you cannot reach still plays.
            log.notice("Share sync skipped: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Keeping a pad change

    /// What the pad is doing differs from what the loaded song says, so the
    /// card can offer to keep it. Covers both halves: whether a pad plays at
    /// all, and in which key.
    public struct PadChange: Sendable, Equatable {
        public var title: String
        public var enablesPad: Bool
        public var changesKey: Bool
        public var key: MusicalKey
        public var changesSound: Bool
        public var sound: PadSound
    }

    public var pendingPadChange: PadChange? {
        guard let item = metronome.loadedItem else { return nil }

        let armed = metronome.isPadArmed
        let keyChanged = !metronome.padFollowsSong && item.key != metronome.padKey
        // Only once a voice has been picked by hand, and only while a pad is
        // actually in play for this song - otherwise every song would be
        // offered a voice it never asked for.
        let soundChanged = !metronome.padSoundFollowsSong
            && armed
            && item.song.padSound != metronome.padSound
        guard armed != item.song.playsPad || keyChanged || soundChanged else { return nil }

        return PadChange(title: item.song.title, enablesPad: armed,
                         changesKey: keyChanged, key: metronome.padKey,
                         changesSound: soundChanged, sound: metronome.padSound)
    }

    /// Writes the pad's current state onto the loaded song.
    ///
    /// A key saved here also clears any key set for this service placement,
    /// which would otherwise keep winning and make the save look ignored - the
    /// same rule as saving a tapped tempo.
    public func savePadToLoadedSong() {
        guard let loaded = metronome.loadedItem, let change = pendingPadChange else { return }

        var song = loaded.song
        song.padEnabled = change.enablesPad ? true : nil
        if change.changesKey { song.defaultKey = change.key }
        if change.changesSound || (change.enablesPad && song.padSound == nil) {
            song.padSound = change.sound
        }
        library.updateSong(song)

        var item = loaded.item
        if change.changesKey, item.key != nil, let serviceID = metronome.loadedServiceID {
            item.key = nil
            library.updateItem(item, in: serviceID)
        }

        if let refreshed = library.resolved(item) {
            metronome.load(refreshed, serviceID: metronome.loadedServiceID)
        }
        // The song now says what the pad was doing, so neither override is
        // needed any more.
        metronome.padManualOn = false
        metronome.resumePadFollowingSong()
    }

    /// Loads the nth song of the service on screen, counting from 1.
    ///
    /// The number keys are how you jump around a set list mid-service without
    /// looking - hence counting from 1, matching the numbers printed on the
    /// rows, rather than from 0.
    @discardableResult
    public func loadSong(atServicePosition position: Int) -> Bool {
        guard let serviceID = selectedServiceID ?? metronome.loadedServiceID else { return false }
        let items = library.resolvedItems(in: serviceID)
        let index = position - 1
        guard items.indices.contains(index) else { return false }
        metronome.load(items[index], serviceID: serviceID)
        return true
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
