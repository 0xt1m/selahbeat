import Foundation

/// Namespaced song identity. The prefix tells you where a song came from
/// without a lookup, and keeps user-created songs from ever colliding with
/// catalog slugs.
public struct SongID: Hashable, Codable, Sendable, RawRepresentable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }

    public static func local(_ uuid: UUID = UUID()) -> SongID {
        SongID(rawValue: "local:\(uuid.uuidString)")
    }

    public static func catalog(_ slug: String) -> SongID {
        SongID(rawValue: "catalog:\(slug)")
    }

    public var isCatalog: Bool { rawValue.hasPrefix("catalog:") }
    public var isLocal: Bool { rawValue.hasPrefix("local:") }

    /// The server slug, for a catalog song.
    public var catalogSlug: String? {
        isCatalog ? String(rawValue.dropFirst("catalog:".count)) : nil
    }

    public var description: String { rawValue }
}
