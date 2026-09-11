import Foundation
import OSLog

/// Keeps the local copy of the shared catalog up to date.
///
/// The catalog is a lookup source and nothing more. Syncing refreshes what a
/// search will *suggest*; it never modifies a song already in the user's
/// library. A tempo corrected on the server changes what the next search
/// offers, and leaves every phone that already added that song alone.
///
/// Never blocks launch and never surfaces an error dialog - a metronome that
/// interrupts a service with a network alert is worse than one that is out of
/// date.
@MainActor
public final class CatalogSync {
    private let service: CatalogServing
    private let cache: CatalogCache
    private let log = Logger(subsystem: "app.selahbeat", category: "catalog-sync")

    public private(set) var isSyncing = false
    public private(set) var lastError: String?

    /// How stale the catalog may be before a background sync runs.
    ///
    /// Six hours was far too long: a tempo corrected in the admin site would
    /// not reach the app for most of a day, which is useless when you are
    /// fixing it because a service is about to start.
    private let minimumInterval: TimeInterval = 15 * 60

    public init(service: CatalogServing, cache: CatalogCache) {
        self.service = service
        self.cache = cache
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
            cache.apply(delta: delta)
            lastError = nil
            log.info("Catalog synced to revision \(self.cache.revision)")
        } catch {
            lastError = error.localizedDescription
            log.notice("Catalog sync failed (offline is fine): \(error.localizedDescription)")
        }
    }
}
