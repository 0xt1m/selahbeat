import Foundation

/// One song's placement in a service.
///
/// `id` is deliberately separate from `songID`: the same song can legitimately
/// appear twice in one service (opener and closer), and SwiftUI's ForEach and
/// drag-reorder need stable per-row identity.
public struct ServiceItem: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var songID: SongID
    /// The key this team plays it in this week — placement data, not song data.
    public var key: MusicalKey?
    public var bpmOverride: Double?
    public var timeSignatureOverride: TimeSignature?
    public var notes: String?

    public init(
        id: UUID = UUID(),
        songID: SongID,
        key: MusicalKey? = nil,
        bpmOverride: Double? = nil,
        timeSignatureOverride: TimeSignature? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.songID = songID
        self.key = key
        self.bpmOverride = bpmOverride
        self.timeSignatureOverride = timeSignatureOverride
        self.notes = notes
    }
}

/// A set list. Order is array order — no `order: Int` field to drift out of
/// sync, and it maps 1:1 onto SwiftUI's `.onMove`.
public struct Service: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var date: Date?
    public var items: [ServiceItem]
    public var notes: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        date: Date? = nil,
        items: [ServiceItem] = [],
        notes: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.date = date
        self.items = items
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// A ServiceItem joined with its Song, with overrides already resolved.
/// This is what the transport consumes — it should never have to think about
/// where a value came from.
public struct ResolvedItem: Identifiable, Hashable, Sendable {
    public let item: ServiceItem
    public let song: Song

    public init(item: ServiceItem, song: Song) {
        self.item = item
        self.song = song
    }

    public var id: UUID { item.id }
    public var title: String { song.title }
    public var bpm: Double { item.bpmOverride ?? song.defaultBPM }
    public var timeSignature: TimeSignature { item.timeSignatureOverride ?? song.defaultTimeSignature }
    public var key: MusicalKey? { item.key ?? song.defaultKey }

    public var hasBPMOverride: Bool { item.bpmOverride != nil }
    public var hasTimeSignatureOverride: Bool { item.timeSignatureOverride != nil }
}
