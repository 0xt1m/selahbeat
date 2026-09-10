import Foundation
import OSLog

/// Atomic, backed-up JSON persistence for one file.
///
/// Durability rules, in order of importance:
///  1. Encode fully into Data before touching disk, so a failed encode can
///     never truncate a good file.
///  2. Write with `.atomic`, which is a temp-file write plus rename(2) - a
///     force-quit or power loss leaves either the old file or the new one.
///  3. Keep one generation of backup and fall back to it if the primary fails
///     to decode.
public struct JSONFileStore<Payload: Codable & Sendable>: Sendable {
    public let url: URL
    private let log = Logger(subsystem: "app.selahbeat", category: "persistence")

    public init(url: URL) {
        self.url = url
    }

    private var backupURL: URL { url.appendingPathExtension("bak") }

    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public func load() -> Payload? {
        let decoder = Self.makeDecoder()
        if let data = try? Data(contentsOf: url) {
            do {
                return try decoder.decode(Payload.self, from: data)
            } catch {
                log.error("Primary store at \(url.lastPathComponent, privacy: .public) failed to decode: \(error.localizedDescription)")
            }
        }
        if let data = try? Data(contentsOf: backupURL) {
            do {
                let recovered = try decoder.decode(Payload.self, from: data)
                log.notice("Recovered \(url.lastPathComponent, privacy: .public) from backup")
                return recovered
            } catch {
                log.error("Backup also failed to decode: \(error.localizedDescription)")
            }
        }
        return nil
    }

    public func save(_ payload: Payload) throws {
        // Encode first. Never let a failed encode destroy a good file.
        let data = try Self.makeEncoder().encode(payload)

        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: backupURL)
            try? FileManager.default.copyItem(at: url, to: backupURL)
        }

        try data.write(to: url, options: [.atomic])
    }
}

/// Where SelahBeat keeps its data. Identical on macOS and iOS; on iOS this
/// lands in the app container, so it is included in device backups.
public enum StoreLocation {
    public static func applicationSupportDirectory() -> URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory())

        let bundleID = Bundle.main.bundleIdentifier ?? "app.selahbeat.SelahBeat"
        let directory = base.appendingPathComponent(bundleID, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
