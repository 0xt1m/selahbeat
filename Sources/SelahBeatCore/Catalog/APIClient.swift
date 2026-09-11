import Foundation
import OSLog

public struct APIClient: CatalogServing {
    public let baseURL: URL
    private let session: URLSession
    private let auth: AuthTokenProviding
    private let appVersion: String

    public init(
        baseURL: URL,
        auth: AuthTokenProviding = NoAuth(),
        appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    ) {
        self.baseURL = baseURL
        self.auth = auth
        self.appVersion = appVersion

        let config = URLSessionConfiguration.default
        // Fail fast when offline rather than hanging a task. Reachability is
        // only ever a hint; the timeout is what actually protects the UI.
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 15
        config.httpAdditionalHeaders = ["User-Agent": "SelahBeat/\(appVersion)"]
        self.session = URLSession(configuration: config)
    }

    private func request(_ path: String, query: [URLQueryItem] = []) async throws -> Data {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw URLError(.badURL) }

        var req = URLRequest(url: url)
        // The catalog endpoint sets a short max-age for crowds of simultaneous
        // launches, but an explicit refresh must never be answered from the
        // local cache - that is exactly the staleness we are trying to fix.
        req.cachePolicy = .reloadIgnoringLocalCacheData
        if let token = await auth.token() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            throw URLError(.init(rawValue: http.statusCode))
        }
        return data
    }

    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    public func fetchDelta(since revision: Int) async throws -> CatalogDelta {
        let data = try await request("v1/catalog", query: [
            URLQueryItem(name: "since", value: String(revision))
        ])
        return try Self.decoder().decode(CatalogDelta.self, from: data)
    }

    public func search(_ query: String, limit: Int) async throws -> [CatalogSong] {
        let data = try await request("v1/songs/search", query: [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(limit)),
        ])
        struct Envelope: Decodable { let songs: [FailableDecodable<CatalogSong>] }
        let envelope = try Self.decoder().decode(Envelope.self, from: data)
        return envelope.songs.compactMap(\.value)
    }
}
