import Foundation
import OSLog

public struct LibraryPayload: Codable, Sendable {
    public var schemaVersion: Int
    public var songs: [Song]
    public var recent: [SongID]

    public init(schemaVersion: Int = 1, songs: [Song] = [], recent: [SongID] = []) {
        self.schemaVersion = schemaVersion
        self.songs = songs
        self.recent = recent
    }
}

public struct ServicesPayload: Codable, Sendable {
    public var schemaVersion: Int
    public var services: [Service]

    public init(schemaVersion: Int = 1, services: [Service] = []) {
        self.schemaVersion = schemaVersion
        self.services = services
    }
}

/// Debounced writer. Mutations mark state dirty; the actual disk write happens
/// 400 ms after the last edit, or immediately on quit/background. Worst-case
/// loss is 400 ms of typing.
public actor PersistenceCoordinator {
    private let libraryStore: JSONFileStore<LibraryPayload>
    private let servicesStore: JSONFileStore<ServicesPayload>
    private let log = Logger(subsystem: "app.selahbeat", category: "persistence")

    private var pendingLibrary: LibraryPayload?
    private var pendingServices: ServicesPayload?
    private var flushTask: Task<Void, Never>?

    private let debounceNanos: UInt64 = 400_000_000

    public init(directory: URL = StoreLocation.applicationSupportDirectory()) {
        self.libraryStore = JSONFileStore(url: directory.appendingPathComponent("library.v1.json"))
        self.servicesStore = JSONFileStore(url: directory.appendingPathComponent("services.v1.json"))
    }

    public func loadLibrary() -> LibraryPayload {
        libraryStore.load() ?? LibraryPayload()
    }

    public func loadServices() -> ServicesPayload {
        servicesStore.load() ?? ServicesPayload()
    }

    public func scheduleLibrarySave(_ payload: LibraryPayload) {
        pendingLibrary = payload
        scheduleFlush()
    }

    public func scheduleServicesSave(_ payload: ServicesPayload) {
        pendingServices = payload
        scheduleFlush()
    }

    private func scheduleFlush() {
        flushTask?.cancel()
        flushTask = Task { [debounceNanos] in
            try? await Task.sleep(nanoseconds: debounceNanos)
            guard !Task.isCancelled else { return }
            await self.flush()
        }
    }

    /// Writes anything pending right now. Call on quit and on backgrounding.
    public func flush() {
        if let payload = pendingLibrary {
            do {
                try libraryStore.save(payload)
                pendingLibrary = nil
            } catch {
                log.error("Library save failed: \(error.localizedDescription)")
            }
        }
        if let payload = pendingServices {
            do {
                try servicesStore.save(payload)
                pendingServices = nil
            } catch {
                log.error("Services save failed: \(error.localizedDescription)")
            }
        }
    }
}
