import Foundation

/// Normalises a string for matching: diacritic- and case-insensitive,
/// punctuation stripped, whitespace collapsed. So "Who You Say I Am" matches
/// "who you say i am" and "What A Beautiful Name" matches "beautiful name".
public func normalizedForSearch(_ raw: String) -> String {
    let folded = raw.folding(
        options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
        locale: .current
    )
    let scalars = folded.unicodeScalars.map { scalar -> Character in
        if CharacterSet.alphanumerics.contains(scalar) { return Character(scalar) }
        return " "
    }
    return String(scalars)
        .split(separator: " ", omittingEmptySubsequences: true)
        .joined(separator: " ")
}

/// How well a candidate matched, best first. Ranking is deliberately explicit
/// rather than a fuzzy score — a drummer typing three letters wants the song
/// that starts with them, not the cleverest match.
public enum MatchRank: Int, Comparable, Sendable {
    case exactTitle = 0
    case titlePrefix = 1
    case titleWordPrefix = 2
    case titleSubstring = 3
    case artistPrefix = 4
    case artistSubstring = 5

    public static func < (lhs: MatchRank, rhs: MatchRank) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// One song's precomputed search keys.
public struct IndexEntry: Sendable {
    public let id: SongID
    public let title: String
    public let words: [String]
    public let artist: String?

    public init(id: SongID, title: String, artist: String?) {
        self.id = id
        self.title = normalizedForSearch(title)
        self.words = self.title.split(separator: " ").map(String.init)
        self.artist = artist.map(normalizedForSearch)
    }

    public init(song: Song) {
        self.init(id: song.id, title: song.title, artist: song.artist)
    }

    public func rank(for query: String) -> MatchRank? {
        guard !query.isEmpty else { return nil }
        if title == query { return .exactTitle }
        if title.hasPrefix(query) { return .titlePrefix }
        if words.contains(where: { $0.hasPrefix(query) }) { return .titleWordPrefix }
        if title.contains(query) { return .titleSubstring }
        if let artist {
            if artist.hasPrefix(query) { return .artistPrefix }
            if artist.contains(query) { return .artistSubstring }
        }
        return nil
    }
}

/// An in-memory index over the whole library.
///
/// A linear scan sounds naive but is the right answer at this size: 2,000
/// songs is ~500 KB and a scan takes tens of microseconds, so search can run
/// synchronously on every keystroke with no debounce and no database round
/// trip. Revisit only if the catalog cache passes ~20,000 entries.
public struct SearchIndex: Sendable {
    private var entries: [SongID: IndexEntry] = [:]

    public init() {}

    public init(songs: some Sequence<Song>) {
        for song in songs { entries[song.id] = IndexEntry(song: song) }
    }

    public var count: Int { entries.count }

    public mutating func update(_ song: Song) {
        entries[song.id] = IndexEntry(song: song)
    }

    public mutating func update(_ entry: IndexEntry) {
        entries[entry.id] = entry
    }

    public mutating func rebuild(with entries: [IndexEntry]) {
        self.entries.removeAll(keepingCapacity: true)
        for entry in entries { self.entries[entry.id] = entry }
    }

    public mutating func remove(_ id: SongID) {
        entries.removeValue(forKey: id)
    }

    public mutating func rebuild(with songs: some Sequence<Song>) {
        entries.removeAll(keepingCapacity: true)
        for song in songs { entries[song.id] = IndexEntry(song: song) }
    }

    /// Returns matching song IDs, best match first. `recency` breaks ties so
    /// songs the drummer actually uses float up.
    public func search(_ rawQuery: String, recency: [SongID: Int] = [:], limit: Int = 50) -> [SongID] {
        let query = normalizedForSearch(rawQuery)
        guard !query.isEmpty else { return [] }

        var scored: [(SongID, MatchRank, Int)] = []
        scored.reserveCapacity(min(entries.count, limit * 4))

        for (id, entry) in entries {
            if let rank = entry.rank(for: query) {
                scored.append((id, rank, recency[id] ?? Int.max))
            }
        }

        scored.sort { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            if lhs.2 != rhs.2 { return lhs.2 < rhs.2 }
            return lhs.0.rawValue < rhs.0.rawValue
        }

        return scored.prefix(limit).map(\.0)
    }
}
