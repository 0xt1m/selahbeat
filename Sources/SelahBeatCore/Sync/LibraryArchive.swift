import Foundation

/// A whole library in one file.
///
/// The escape hatch that depends on nothing: no account, no server, no
/// network. It is also the only form of backup that outlives the service -
/// a file on a disk keeps working whatever happens to selahbeat.com.
public struct LibraryArchive: Codable, Sendable {
    public static let fileExtension = "selahbeat"
    public static let currentVersion = 1

    public var version: Int
    public var exportedAt: Date
    public var songs: [Song]
    public var services: [Service]

    public init(songs: [Song], services: [Service], exportedAt: Date = Date()) {
        self.version = Self.currentVersion
        self.exportedAt = exportedAt
        self.songs = songs
        self.services = services
    }

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        // Readable on purpose: someone opening this in a text editor years
        // from now should be able to see what their set lists were.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public func data() throws -> Data {
        try Self.encoder().encode(self)
    }

    public static func read(from data: Data) throws -> LibraryArchive {
        try decoder().decode(LibraryArchive.self, from: data)
    }

    /// A name that sorts by date and says what it is.
    public var suggestedFilename: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "SelahBeat \(formatter.string(from: exportedAt)).\(Self.fileExtension)"
    }
}

/// What an import did, so the app can say so plainly rather than claiming
/// success and leaving the user to count.
public struct ImportSummary: Sendable, Equatable {
    public var songsAdded = 0
    public var songsSkipped = 0
    public var servicesAdded = 0
    public var servicesSkipped = 0

    public var isEmpty: Bool {
        songsAdded == 0 && servicesAdded == 0 && songsSkipped == 0 && servicesSkipped == 0
    }

    public var summary: String {
        var parts: [String] = []
        if songsAdded > 0 { parts.append("\(songsAdded) song\(songsAdded == 1 ? "" : "s")") }
        if servicesAdded > 0 { parts.append("\(servicesAdded) service\(servicesAdded == 1 ? "" : "s")") }
        let skipped = songsSkipped + servicesSkipped
        if parts.isEmpty { return skipped > 0 ? "Everything in that file was already here" : "Nothing to import" }
        let added = "Added " + parts.joined(separator: " and ")
        return skipped > 0 ? "\(added); \(skipped) already here" : added
    }
}
