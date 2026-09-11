import Foundation
import Observation

/// The user's songs and services, held entirely in memory.
///
/// Loading is synchronous at init: ~5 ms is well inside the launch budget and
/// it removes an empty-state flash plus a whole class of "is it loaded yet"
/// bugs.
@MainActor
@Observable
public final class LibraryStore {
    public private(set) var songs: [SongID: Song] = [:]
    public private(set) var services: [Service] = []
    /// Most-recently-used first. Drives the default rows in the add-song sheet
    /// and breaks search ties.
    public private(set) var recentSongIDs: [SongID] = []

    private var index = SearchIndex()
    private let persistence: PersistenceCoordinator

    public init(persistence: PersistenceCoordinator = PersistenceCoordinator(), autoload: Bool = true) {
        self.persistence = persistence
        if autoload {
            // Synchronous load via a semaphore-free bootstrap: the actor call is
            // awaited by the caller through `bootstrap()` instead.
        }
    }

    /// Loads from disk. Call once at launch before showing UI.
    public func bootstrap() async {
        let library = await persistence.loadLibrary()
        let servicesPayload = await persistence.loadServices()

        var byID: [SongID: Song] = [:]
        for song in library.songs { byID[song.id] = song }
        songs = byID
        recentSongIDs = library.recent.filter { byID[$0] != nil }
        services = servicesPayload.services
        index.rebuild(with: byID.values)
    }

    // MARK: - Derived

    public var allSongs: [Song] {
        songs.values.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    public var recentSongs: [Song] {
        recentSongIDs.compactMap { songs[$0] }
    }

    public var sortedServices: [Service] {
        services.sorted { lhs, rhs in
            let l = lhs.date ?? lhs.createdAt
            let r = rhs.date ?? rhs.createdAt
            if l != r { return l > r }
            return lhs.createdAt > rhs.createdAt
        }
    }

    public func song(_ id: SongID) -> Song? { songs[id] }

    public func service(_ id: UUID) -> Service? {
        services.first { $0.id == id }
    }

    public func resolved(_ item: ServiceItem) -> ResolvedItem? {
        guard let song = songs[item.songID] else { return nil }
        return ResolvedItem(item: item, song: song)
    }

    public func resolvedItems(in serviceID: UUID) -> [ResolvedItem] {
        guard let service = service(serviceID) else { return [] }
        return service.items.compactMap { resolved($0) }
    }

    /// How many services reference a song — shown before deleting one.
    public func usageCount(of id: SongID) -> Int {
        services.reduce(0) { total, service in
            total + service.items.filter { $0.songID == id }.count
        }
    }

    // MARK: - Search

    private var recencyMap: [SongID: Int] {
        var map: [SongID: Int] = [:]
        for (offset, id) in recentSongIDs.enumerated() { map[id] = offset }
        return map
    }

    /// Synchronous by design — runs on every keystroke with no debounce.
    public func search(_ query: String, limit: Int = 50) -> [Song] {
        index.search(query, recency: recencyMap, limit: limit).compactMap { songs[$0] }
    }

    // MARK: - Song mutations

    @discardableResult
    public func addSong(_ song: Song) -> Song {
        var stored = song
        stored.updatedAt = Date()
        songs[stored.id] = stored
        index.update(stored)
        noteUse(stored.id)
        saveLibrary()
        return stored
    }

    public func updateSong(_ song: Song) {
        var stored = song
        stored.updatedAt = Date()
        songs[stored.id] = stored
        index.update(stored)
        saveLibrary()
    }

    public func deleteSong(_ id: SongID) {
        songs.removeValue(forKey: id)
        index.remove(id)
        recentSongIDs.removeAll { $0 == id }
        for i in services.indices {
            let before = services[i].items.count
            services[i].items.removeAll { $0.songID == id }
            if services[i].items.count != before { services[i].updatedAt = Date() }
        }
        saveLibrary()
        saveServices()
    }

    /// Copies a song into a new, independent song.
    ///
    /// Keeps the title as-is rather than appending "copy": two songs sharing a
    /// name and differing in tempo is a supported arrangement, not an accident.
    /// Callers generally open the editor on the result so it can be retuned.
    @discardableResult
    public func duplicateSong(_ id: SongID) -> Song? {
        guard let original = songs[id] else { return nil }
        var copy = original
        copy.id = .local()
        copy.createdAt = Date()
        copy.updatedAt = Date()
        return addSong(copy)
    }

    public func noteUse(_ id: SongID) {
        recentSongIDs.removeAll { $0 == id }
        recentSongIDs.insert(id, at: 0)
        if recentSongIDs.count > 30 { recentSongIDs.removeLast(recentSongIDs.count - 30) }
    }

    // MARK: - Service mutations

    /// Services are almost always named after a date, so offer the next Sunday.
    public func suggestedServiceName(from today: Date = Date()) -> String {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: today)
        let daysUntilSunday = (8 - weekday) % 7
        let target = calendar.date(byAdding: .day, value: daysUntilSunday, to: today) ?? today
        return "Service \(target.formatted(.dateTime.month(.abbreviated).day()))"
    }

    @discardableResult
    public func createService(name: String, date: Date? = Date()) -> Service {
        let service = Service(name: name, date: date)
        services.append(service)
        saveServices()
        return service
    }

    public func updateService(_ service: Service) {
        guard let idx = services.firstIndex(where: { $0.id == service.id }) else { return }
        var updated = service
        updated.updatedAt = Date()
        services[idx] = updated
        saveServices()
    }

    public func deleteService(_ id: UUID) {
        services.removeAll { $0.id == id }
        saveServices()
    }

    /// "Copy last week's service" — the single most common real-world action.
    @discardableResult
    public func duplicateService(_ id: UUID, newName: String? = nil) -> Service? {
        guard let source = service(id) else { return nil }
        var copy = source
        copy.id = UUID()
        copy.name = newName ?? "\(source.name) copy"
        copy.date = Date()
        copy.createdAt = Date()
        copy.updatedAt = Date()
        // Fresh placement identities, same songs, same keys.
        copy.items = source.items.map { item in
            var new = item
            new.id = UUID()
            return new
        }
        services.append(copy)
        saveServices()
        return copy
    }

    @discardableResult
    public func addSong(_ songID: SongID, to serviceID: UUID, key: MusicalKey? = nil) -> ServiceItem? {
        guard let idx = services.firstIndex(where: { $0.id == serviceID }) else { return nil }
        let item = ServiceItem(songID: songID, key: key)
        services[idx].items.append(item)
        services[idx].updatedAt = Date()
        noteUse(songID)
        saveServices()
        saveLibrary()
        return item
    }

    public func removeItem(_ itemID: UUID, from serviceID: UUID) {
        guard let idx = services.firstIndex(where: { $0.id == serviceID }) else { return }
        services[idx].items.removeAll { $0.id == itemID }
        services[idx].updatedAt = Date()
        saveServices()
    }

    /// Reorder. Array order IS the order — there is no index field to renumber.
    public func moveItems(in serviceID: UUID, from offsets: IndexSet, to destination: Int) {
        guard let idx = services.firstIndex(where: { $0.id == serviceID }) else { return }
        services[idx].items.moveElements(fromOffsets: offsets, toOffset: destination)
        services[idx].updatedAt = Date()
        saveServices()
    }

    public func updateItem(_ item: ServiceItem, in serviceID: UUID) {
        guard let sIdx = services.firstIndex(where: { $0.id == serviceID }),
              let iIdx = services[sIdx].items.firstIndex(where: { $0.id == item.id }) else { return }
        services[sIdx].items[iIdx] = item
        services[sIdx].updatedAt = Date()
        saveServices()
    }

    // MARK: - Persistence

    private func saveLibrary() {
        let payload = LibraryPayload(songs: Array(songs.values), recent: recentSongIDs)
        Task { await persistence.scheduleLibrarySave(payload) }
    }

    private func saveServices() {
        let payload = ServicesPayload(services: services)
        Task { await persistence.scheduleServicesSave(payload) }
    }

    /// Call on quit and on backgrounding.
    public func flush() async {
        await persistence.flush()
    }
}
