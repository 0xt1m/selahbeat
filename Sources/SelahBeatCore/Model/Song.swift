import Foundation

public enum SongOrigin: Codable, Hashable, Sendable {
    case custom
    case catalog(catalogID: String, revision: Int, fetchedAt: Date)

    public var isCatalog: Bool {
        if case .catalog = self { return true }
        return false
    }

    public var catalogID: String? {
        if case .catalog(let id, _, _) = self { return id }
        return nil
    }
}

/// A song in the user's local library. Everything here is offline-first: once
/// a song is in the library it never needs the network again.
public struct Song: Identifiable, Codable, Hashable, Sendable {
    public var id: SongID
    public var title: String
    public var artist: String?
    public var defaultBPM: Double
    public var defaultTimeSignature: TimeSignature
    /// The song's own key, informational. The key a team plays it in lives on
    /// the ServiceItem, not here.
    public var defaultKey: MusicalKey?
    public var origin: SongOrigin
    public var notes: String?
    /// Set the moment the user edits an imported song, so a later catalog
    /// correction can never silently overwrite a deliberate local change.
    public var isUserModified: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: SongID = .local(),
        title: String,
        artist: String? = nil,
        defaultBPM: Double,
        defaultTimeSignature: TimeSignature = .fourFour,
        defaultKey: MusicalKey? = nil,
        origin: SongOrigin = .custom,
        notes: String? = nil,
        isUserModified: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.defaultBPM = Song.clampBPM(defaultBPM)
        self.defaultTimeSignature = defaultTimeSignature
        self.defaultKey = defaultKey
        self.origin = origin
        self.notes = notes
        self.isUserModified = isUserModified
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public static let minBPM: Double = 20
    public static let maxBPM: Double = 400

    public static func clampBPM(_ bpm: Double) -> Double {
        guard bpm.isFinite else { return 120 }
        return min(max(bpm, minBPM), maxBPM)
    }
}
