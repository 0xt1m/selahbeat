import Foundation
import Observation
import OSLog

/// Backup and sharing, from the app's side.
///
/// Everything here is best-effort and never on the path of anything the
/// drummer is doing: the library is always saved locally first, and this
/// catches up whenever there is a network. Offline for a month is a longer
/// queue, not an error.
@MainActor
@Observable
public final class BackupService {
    public enum State: Sendable, Equatable {
        case idle
        case working
        case failed(String)
    }

    public private(set) var state: State = .idle
    public private(set) var lastSync: Date?
    public private(set) var recoveryCode: String?
    /// Server revision this device has already seen.
    public private(set) var revision: Int

    private let identity: SyncIdentity
    private let client: SyncClient
    private let library: LibraryStore
    private let log = Logger(subsystem: "app.selahbeat", category: "backup")
    private let defaults = UserDefaults.standard
    private let revisionKey = "app.selahbeat.sync.revision"

    public init(identity: SyncIdentity, client: SyncClient, library: LibraryStore) {
        self.identity = identity
        self.client = client
        self.library = library
        self.revision = defaults.integer(forKey: revisionKey)
    }

    public var isRegistered: Bool { identity.isRegistered }
    public var accountId: String? { identity.credentials?.accountId }

    // MARK: - Account

    /// Creates the account on first use. Returns the recovery code, which is
    /// the only moment it is handed out in full by the server.
    @discardableResult
    public func registerIfNeeded() async throws -> SyncCredentials {
        if let existing = identity.credentials { return existing }

        let registration = try await client.register()
        let credentials = SyncCredentials(accountId: registration.accountId,
                                          deviceId: registration.deviceId,
                                          secret: registration.secret)
        identity.store(credentials)
        recoveryCode = registration.recoveryCode
        return credentials
    }

    /// Adopts an existing account on this device, then pulls everything down.
    public func restore(withCode code: String) async throws -> ImportSummary {
        state = .working
        defer { if state == .working { state = .idle } }

        let registration = try await client.recover(code: code)
        identity.store(SyncCredentials(accountId: registration.accountId,
                                       deviceId: registration.deviceId,
                                       secret: registration.secret))
        setRevision(0)
        return try await pullEverything()
    }

    /// Asks the server for a fresh code, retiring the old one.
    public func refreshRecoveryCode() async throws -> String {
        let credentials = try await registerIfNeeded()
        let code = try await client.newRecoveryCode(token: credentials.token)
        recoveryCode = code
        return code
    }

    public func deleteEverythingOnServer() async throws {
        guard let credentials = identity.credentials else { return }
        try await client.deleteEverything(token: credentials.token)
        identity.forget()
        setRevision(0)
        recoveryCode = nil
    }

    // MARK: - Backup

    /// Pushes the whole library, then pulls anything this device has not seen.
    ///
    /// Sending everything rather than a delta is deliberate for now: a library
    /// is a few hundred kilobytes, the server settles conflicts by timestamp,
    /// and it means a missed change can never go unnoticed forever.
    public func syncNow() async throws -> ImportSummary {
        let credentials = try await registerIfNeeded()
        state = .working
        defer { if state == .working { state = .idle } }

        let documents = try outgoingDocuments()
        if !documents.isEmpty {
            let result = try await client.push(token: credentials.token, documents: documents)
            setRevision(result.revision)
            for rejection in result.rejected {
                log.notice("Server kept its own copy of \(rejection.id, privacy: .public): \(rejection.reason, privacy: .public)")
            }
        }

        let summary = try await pullEverything()
        lastSync = Date()
        return summary
    }

    private func pullEverything() async throws -> ImportSummary {
        guard let credentials = identity.credentials else { return ImportSummary() }

        var summary = ImportSummary()
        var since = revision
        var pages = 0

        repeat {
            let page = try await client.pull(token: credentials.token, since: since)
            summary = merge(page.documents, into: summary)
            since = page.revision
            pages += 1
            if page.more != true { break }
        } while pages < 50

        setRevision(since)
        lastSync = Date()
        return summary
    }

    // MARK: - Documents

    private func outgoingDocuments() throws -> [SyncClient.Document] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let formatter = ISO8601DateFormatter()

        var documents: [SyncClient.Document] = []
        for song in library.allSongs {
            documents.append(SyncClient.Document(
                id: song.id.rawValue,
                kind: "song",
                body: try JSONValue.encoding(song, using: encoder),
                deleted: false,
                clientUpdatedAt: formatter.string(from: song.updatedAt)
            ))
        }
        for service in library.sortedServices {
            documents.append(SyncClient.Document(
                id: service.id.uuidString,
                kind: "service",
                body: try JSONValue.encoding(service, using: encoder),
                deleted: false,
                clientUpdatedAt: formatter.string(from: service.updatedAt)
            ))
        }
        return documents
    }

    private func merge(_ documents: [SyncClient.Document], into summary: ImportSummary) -> ImportSummary {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var songs: [Song] = []
        var services: [Service] = []

        for document in documents where document.deleted != true {
            switch document.kind {
            case "song":
                if let song = try? document.body.decoded(Song.self, using: decoder) { songs.append(song) }
            case "service":
                if let service = try? document.body.decoded(Service.self, using: decoder) { services.append(service) }
            default:
                // A kind this build does not know about belongs to a newer one;
                // leaving it alone is better than guessing at it.
                continue
            }
        }

        let result = library.importArchive(LibraryArchive(songs: songs, services: services))
        return ImportSummary(
            songsAdded: summary.songsAdded + result.songsAdded,
            songsSkipped: summary.songsSkipped + result.songsSkipped,
            servicesAdded: summary.servicesAdded + result.servicesAdded,
            servicesSkipped: summary.servicesSkipped + result.servicesSkipped
        )
    }

    private func setRevision(_ value: Int) {
        revision = value
        defaults.set(value, forKey: revisionKey)
    }
}
