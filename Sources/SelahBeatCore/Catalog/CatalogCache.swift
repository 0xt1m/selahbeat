import Foundation
import Observation
import OSLog

/// The catalog, mirrored to disk.
///
/// Deliberately a full local mirror rather than a per-search network call: a
/// curated catalog of a few thousand songs is a few hundred KB, so syncing it
/// once means tempo lookup keeps working on bad church wifi — which is exactly
/// when a drummer needs it.
@MainActor
@Observable
public final class CatalogCache {
    public private(set) var songs: [String: CatalogSong] = [:]
    public private(set) var revision: Int = 0
    public private(set) var lastSync: Date?

    private var index = SearchIndex()
    private let store: JSONFileStore<CatalogCachePayload>
    private let log = Logger(subsystem: "app.selahbeat", category: "catalog")

    public init(directory: URL = StoreLocation.applicationSupportDirectory()) {
        self.store = JSONFileStore(url: directory.appendingPathComponent("catalog-cache.v1.json"))
    }

    public var count: Int { songs.count }

    public func bootstrap() {
        if let payload = store.load() {
            apply(payload)
        } else {
            loadBundledSeed()
        }
    }

    private func apply(_ payload: CatalogCachePayload) {
        var byID: [String: CatalogSong] = [:]
        for song in payload.songs { byID[song.id] = song }
        songs = byID
        revision = payload.revision
        lastSync = payload.lastSync
        rebuildIndex()
    }

    /// Ships a starter catalog inside the app so song lookup works on a fresh
    /// install with no network and before the server exists.
    private func loadBundledSeed() {
        guard let url = Bundle.module.url(forResource: "seed-songs", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            log.notice("No bundled seed catalog found")
            return
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            struct Seed: Decodable { let revision: Int; let songs: [FailableDecodable<CatalogSong>] }
            let seed = try decoder.decode(Seed.self, from: data)
            var byID: [String: CatalogSong] = [:]
            for song in seed.songs.compactMap(\.value) { byID[song.id] = song }
            songs = byID
            revision = 0   // 0 so the first sync still pulls a full snapshot
            rebuildIndex()
            log.info("Loaded \(byID.count) seed songs")
        } catch {
            log.error("Seed catalog failed to decode: \(error.localizedDescription)")
        }
    }

    private func rebuildIndex() {
        index.rebuild(with: songs.values.map {
            IndexEntry(id: $0.songID, title: $0.title, artist: $0.artist)
        })
    }

    /// Synchronous, offline, no debounce.
    public func search(_ query: String, limit: Int = 30) -> [CatalogSong] {
        index.search(query, limit: limit).compactMap { id in
            id.catalogSlug.flatMap { songs[$0] }
        }
    }

    public func song(slug: String) -> CatalogSong? { songs[slug] }

    /// Applies a server delta. Returns the upserts, so the caller can
    /// reconcile any already-imported copies.
    @discardableResult
    public func apply(delta: CatalogDelta) -> [CatalogSong] {
        if delta.full { songs.removeAll(keepingCapacity: true) }
        for song in delta.upserts { songs[song.id] = song }
        for id in delta.deletes { songs.removeValue(forKey: id) }
        revision = delta.revision
        lastSync = Date()
        rebuildIndex()
        persist()
        return delta.upserts
    }

    private func persist() {
        let payload = CatalogCachePayload(
            revision: revision,
            songs: Array(songs.values),
            lastSync: lastSync
        )
        let store = self.store
        Task.detached(priority: .utility) {
            try? store.save(payload)
        }
    }
}
