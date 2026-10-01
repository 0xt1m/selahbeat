import Foundation
import Observation
import OSLog

/// A service shared by code, and the ones you have joined.
///
/// A shared service is self-contained: it carries its own copy of each song's
/// tempo, meter, key and mix, so joining one puts nothing in your library and
/// a band mate's edit can never reach your own songs.
@MainActor
@Observable
public final class ShareService {
    /// What this device knows about a share, kept alongside the service it
    /// belongs to so a reinstall can pick it up again from the server.
    public struct Membership: Codable, Sendable, Equatable, Identifiable {
        public var shareId: String
        public var serviceId: UUID
        public var code: String?        // only the owner is given one to hand out
        public var isOwner: Bool
        public var revision: Int

        public var id: String { shareId }
    }

    public private(set) var memberships: [Membership] = []
    public private(set) var lastError: String?

    private let identity: SyncIdentity
    private let client: SyncClient
    private let library: LibraryStore
    private let log = Logger(subsystem: "app.selahbeat", category: "shares")
    private let defaults = UserDefaults.standard
    private let storageKey = "app.selahbeat.shares"

    public init(identity: SyncIdentity, client: SyncClient, library: LibraryStore) {
        self.identity = identity
        self.client = client
        self.library = library
        load()
    }

    public func membership(forService serviceId: UUID) -> Membership? {
        memberships.first { $0.serviceId == serviceId }
    }

    // MARK: - Sharing one of yours

    /// Publishes a service and returns the code to hand out.
    public func share(serviceId: UUID, token: String) async throws -> String {
        guard let service = library.service(serviceId) else { throw SyncClient.Failure.notFound }

        let created = try await client.createShare(token: token,
                                                   documents: try documents(for: service))
        var updated = memberships.filter { $0.serviceId != serviceId }
        updated.append(Membership(shareId: created.shareId, serviceId: serviceId,
                                  code: created.code, isOwner: true, revision: created.revision))
        memberships = updated
        save()
        return created.code
    }

    public func rotateCode(forService serviceId: UUID, token: String) async throws -> String {
        guard let membership = membership(forService: serviceId), membership.isOwner else {
            throw SyncClient.Failure.notFound
        }
        let code = try await client.rotateCode(token: token, shareId: membership.shareId)
        replace(membership, with: { $0.code = code })
        return code
    }

    public func stopSharing(serviceId: UUID, token: String) async throws {
        guard let membership = membership(forService: serviceId) else { return }
        if membership.isOwner {
            try await client.revokeShare(token: token, shareId: membership.shareId)
        }
        memberships.removeAll { $0.shareId == membership.shareId }
        save()
    }

    // MARK: - Joining someone else's

    /// Joins by code and writes the shared set list into the library as a
    /// service of its own, with its songs as independent copies.
    @discardableResult
    public func join(code: String, token: String) async throws -> Service {
        let contents = try await client.join(token: token, code: code)
        let service = try materialise(contents)

        var updated = memberships.filter { $0.shareId != contents.share.id }
        updated.append(Membership(shareId: contents.share.id, serviceId: service.id,
                                  code: nil, isOwner: contents.share.role == "owner",
                                  revision: contents.revision))
        memberships = updated
        save()
        return service
    }

    /// Pulls anything new on a joined service. Called when its screen opens
    /// and whenever the live stream says something changed.
    @discardableResult
    public func refresh(serviceId: UUID, token: String) async throws -> Bool {
        guard let membership = membership(forService: serviceId) else { return false }

        let contents = try await client.pullShare(token: token, shareId: membership.shareId,
                                                  since: membership.revision)
        guard !contents.documents.isEmpty else { return false }

        _ = try materialise(contents, existingServiceId: serviceId)
        replace(membership, with: { $0.revision = contents.revision })
        return true
    }

    /// Sends local edits of a shared service back up.
    public func push(serviceId: UUID, token: String) async throws {
        guard let membership = membership(forService: serviceId),
              let service = library.service(serviceId) else { return }

        let result = try await client.pushShare(token: token, shareId: membership.shareId,
                                                documents: try documents(for: service))
        replace(membership, with: { $0.revision = result.revision })
        for rejection in result.rejected {
            log.notice("Share kept its own copy of \(rejection.id, privacy: .public): \(rejection.reason, privacy: .public)")
        }
    }

    // MARK: - Documents

    /// A service becomes one document for itself and one per placement, each
    /// carrying the song it points at. Per-item documents are what let two
    /// people add songs at once without overwriting each other.
    private func documents(for service: Service) throws -> [SyncClient.Document] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let formatter = ISO8601DateFormatter()
        let stamp = formatter.string(from: service.updatedAt)

        var documents: [SyncClient.Document] = [
            SyncClient.Document(
                id: service.id.uuidString,
                kind: "service",
                body: try JSONValue.encoding(ServiceHeader(service: service), using: encoder),
                deleted: false,
                clientUpdatedAt: stamp
            )
        ]

        for (position, item) in service.items.enumerated() {
            guard let song = library.song(item.songID) else { continue }
            documents.append(SyncClient.Document(
                id: item.id.uuidString,
                kind: "item",
                body: try JSONValue.encoding(SharedItem(order: position, item: item, song: song),
                                             using: encoder),
                deleted: false,
                clientUpdatedAt: stamp
            ))
        }
        return documents
    }

    private struct ServiceHeader: Codable, Sendable {
        var name: String
        var date: Date?
        var notes: String?

        init(service: Service) {
            name = service.name
            date = service.date
            notes = service.notes
        }
    }

    private struct SharedItem: Codable, Sendable {
        var order: Int
        var itemId: UUID
        var key: MusicalKey?
        var bpmOverride: Double?
        var notes: String?
        var song: Song

        init(order: Int, item: ServiceItem, song: Song) {
            self.order = order
            self.itemId = item.id
            self.key = item.key
            self.bpmOverride = item.bpmOverride
            self.notes = item.notes
            self.song = song
        }
    }

    /// Turns a pulled share into a real service in the library.
    private func materialise(_ contents: SyncClient.ShareContents,
                             existingServiceId: UUID? = nil) throws -> Service {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var header: ServiceHeader?
        var items: [SharedItem] = []

        for document in contents.documents where document.deleted != true {
            switch document.kind {
            case "service": header = try? document.body.decoded(ServiceHeader.self, using: decoder)
            case "item":
                if let item = try? document.body.decoded(SharedItem.self, using: decoder) {
                    items.append(item)
                }
            default: continue
            }
        }
        items.sort { $0.order < $1.order }

        let serviceId = existingServiceId ?? UUID()
        var service = library.service(serviceId)
            ?? library.createService(name: header?.name ?? "Shared service", date: header?.date)
        service.name = header?.name ?? service.name
        service.date = header?.date ?? service.date
        service.notes = header?.notes ?? service.notes

        // Songs arrive as copies owned by this device, which is what keeps a
        // shared set list from reaching into anyone's library.
        var placements: [ServiceItem] = []
        for shared in items {
            let stored = library.song(shared.song.id) ?? library.addSong(shared.song)
            var placement = ServiceItem(songID: stored.id)
            placement.id = shared.itemId
            placement.key = shared.key
            placement.bpmOverride = shared.bpmOverride
            placement.notes = shared.notes
            placements.append(placement)
        }
        service.items = placements
        library.updateService(service)
        return service
    }

    // MARK: - Storage

    private func replace(_ membership: Membership, with change: (inout Membership) -> Void) {
        guard let index = memberships.firstIndex(where: { $0.shareId == membership.shareId }) else { return }
        var updated = memberships[index]
        change(&updated)
        memberships[index] = updated
        save()
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let stored = try? JSONDecoder().decode([Membership].self, from: data) else { return }
        memberships = stored
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(memberships) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
