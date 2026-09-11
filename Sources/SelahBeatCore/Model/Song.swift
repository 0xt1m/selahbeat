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

/// A song in the user's local library.
///
/// Once a song is here it is the user's, permanently. The server catalog is a
/// lookup source for tempos you don't know - it never reaches back in and
/// changes a song you have already added. If the catalog later revises a
/// tempo, that only affects what a future search suggests.
/// Per-song balance between the click layers.
///
/// Deliberately excludes the master level: that is how loud the metronome is in
/// your ears, and having it jump when you load a song would be unpleasant at
/// best and dangerous on stage at worst.
public struct SongMix: Hashable, Codable, Sendable {
    public var accent: Double
    public var quarter: Double
    public var eighth: Double
    public var sixteenth: Double

    public init(accent: Double = 1.0, quarter: Double = 1.0,
                eighth: Double = 0.0, sixteenth: Double = 0.0) {
        self.accent = accent
        self.quarter = quarter
        self.eighth = eighth
        self.sixteenth = sixteenth
    }

    public static let standard = SongMix()
}

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
    /// nil means "whatever the mix is set to"; loading such a song leaves the
    /// current balance alone rather than resetting it.
    public var mix: SongMix?
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
        mix: SongMix? = nil,
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
        self.mix = mix
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
