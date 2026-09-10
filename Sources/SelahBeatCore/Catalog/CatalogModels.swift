import Foundation

/// A song in the shared server catalog. Flat on the wire so the server schema
/// stays a plain SQL row.
public struct CatalogSong: Codable, Hashable, Sendable, Identifiable {
    public var id: String          // stable slug — NEVER reused or renumbered
    public var title: String
    public var artist: String?
    public var bpm: Double
    public var beats: Int
    public var noteValue: Int
    public var key: String?
    public var notes: String?
    public var revision: Int

    public init(
        id: String,
        title: String,
        artist: String? = nil,
        bpm: Double,
        beats: Int = 4,
        noteValue: Int = 4,
        key: String? = nil,
        notes: String? = nil,
        revision: Int = 1
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.bpm = bpm
        self.beats = beats
        self.noteValue = noteValue
        self.key = key
        self.notes = notes
        self.revision = revision
    }

    public var songID: SongID { .catalog(id) }
    public var timeSignature: TimeSignature { TimeSignature(beats: beats, noteValue: noteValue) }
    public var musicalKey: MusicalKey? { key.flatMap(MusicalKey.parse) }

    /// Copies a catalog entry into the local library, where it becomes a
    /// first-class offline song.
    public func toSong() -> Song {
        Song(
            id: songID,
            title: title,
            artist: artist,
            defaultBPM: bpm,
            defaultTimeSignature: timeSignature,
            defaultKey: musicalKey,
            origin: .catalog(catalogID: id, revision: revision, fetchedAt: Date()),
            notes: notes,
            isUserModified: false
        )
    }
}

public struct CatalogDelta: Codable, Sendable {
    public var revision: Int
    public var full: Bool
    public var upserts: [CatalogSong]
    public var deletes: [String]

    public init(revision: Int, full: Bool, upserts: [CatalogSong], deletes: [String] = []) {
        self.revision = revision
        self.full = full
        self.upserts = upserts
        self.deletes = deletes
    }
}

public struct CatalogCachePayload: Codable, Sendable {
    public var schemaVersion: Int
    public var revision: Int
    public var songs: [CatalogSong]
    public var lastSync: Date?

    public init(schemaVersion: Int = 1, revision: Int = 0, songs: [CatalogSong] = [], lastSync: Date? = nil) {
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.songs = songs
        self.lastSync = lastSync
    }
}

/// Decodes an array element-by-element so one malformed row from a newer
/// server can't discard the entire payload.
struct FailableDecodable<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

public protocol CatalogServing: Sendable {
    func fetchDelta(since revision: Int) async throws -> CatalogDelta
    func search(_ query: String, limit: Int) async throws -> [CatalogSong]
}

/// Supplies the bearer token once subscriptions exist. `NoAuth` today.
public protocol AuthTokenProviding: Sendable {
    func token() async -> String?
}

public struct NoAuth: AuthTokenProviding {
    public init() {}
    public func token() async -> String? { nil }
}
