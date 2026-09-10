import Foundation
import OSLog

/// Pulls catalog deltas and reconciles them against already-imported songs.
///
/// Never blocks launch and never surfaces an error dialog — a metronome that
/// interrupts a service with a network alert is worse than one that is simply
/// out of date.
@MainActor
public final class CatalogSync {
    private let service: CatalogServing
    private let cache: CatalogCache
    private let library: LibraryStore
    private let log = Logger(subsystem: "app.selahbeat", category: "catalog-sync")

    public private(set) var isSyncing = false
    public private(set) var lastError: String?
    /// Catalog corrections to songs the user has edited, awaiting their call.
    public private(set) var pendingUpdates: [SongID: CatalogSong] = [:]

    private let minimumInterval: TimeInterval = 6 * 3600

    public init(service: CatalogServing, cache: CatalogCache, library: LibraryStore) {
        self.service = service
        self.cache = cache
        self.library = library
    }

    public func syncIfStale() async {
        if let last = cache.lastSync, Date().timeIntervalSince(last) < minimumInterval { return }
        await sync()
    }

    public func sync() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        do {
            let delta = try await service.fetchDelta(since: cache.revision)
            let upserts = cache.apply(delta: delta)
            reconcile(upserts)
            for id in delta.deletes {
                // A server delete never removes the user's copy; it only leaves
                // the search corpus.
                pendingUpdates.removeValue(forKey: .catalog(id))
            }
            lastError = nil
            log.info("Catalog synced to revision \(self.cache.revision)")
        } catch {
            lastError = error.localizedDescription
            log.notice("Catalog sync failed (offline is fine): \(error.localizedDescription)")
        }
    }

    /// Free corrections for untouched songs; an explicit prompt for edited ones.
    private func reconcile(_ upserts: [CatalogSong]) {
        for incoming in upserts {
            let id = incoming.songID
            guard var existing = library.song(id), existing.origin.isCatalog else { continue }

            if existing.isUserModified {
                pendingUpdates[id] = incoming
                continue
            }

            existing.title = incoming.title
            existing.artist = incoming.artist
            existing.defaultBPM = Song.clampBPM(incoming.bpm)
            existing.defaultTimeSignature = incoming.timeSignature
            existing.defaultKey = incoming.musicalKey
            existing.origin = .catalog(catalogID: incoming.id, revision: incoming.revision, fetchedAt: Date())
            // Bypass updateSong so this doesn't count as a user edit.
            library.applyCatalogRefresh(existing)
        }
    }

    /// The user accepted a pending catalog correction.
    public func applyPendingUpdate(for id: SongID) {
        guard let incoming = pendingUpdates[id], var existing = library.song(id) else { return }
        existing.defaultBPM = Song.clampBPM(incoming.bpm)
        existing.defaultTimeSignature = incoming.timeSignature
        existing.defaultKey = incoming.musicalKey
        existing.origin = .catalog(catalogID: incoming.id, revision: incoming.revision, fetchedAt: Date())
        library.applyCatalogRefresh(existing)
        pendingUpdates.removeValue(forKey: id)
    }

    public func dismissPendingUpdate(for id: SongID) {
        pendingUpdates.removeValue(forKey: id)
    }
}
