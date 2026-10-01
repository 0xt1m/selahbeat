import Foundation

/// The sync and sharing API.
///
/// Every call is explicit about failing: the app must keep working with no
/// network at all, so nothing here is allowed to be on a path that blocks the
/// metronome. Callers treat a thrown error as "try again later".
public struct SyncClient: Sendable {
    public enum Failure: Error, Sendable, Equatable {
        case offline
        case notFound           // a code that matches nothing
        case rateLimited(retryAfter: Int)
        case server(status: Int)
        case malformed
    }

    public let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    // MARK: - Shapes

    public struct Registration: Codable, Sendable {
        public var accountId: String
        public var deviceId: String
        public var secret: String
        public var recoveryCode: String?
    }

    public struct Document: Codable, Sendable {

        public var id: String
        public var kind: String
        public var body: JSONValue
        public var deleted: Bool?
        public var clientUpdatedAt: String
        public var revision: Int?
    }

    public struct Pull: Codable, Sendable {
        public var revision: Int
        public var documents: [Document]
        public var more: Bool?
    }

    public struct PushResult: Codable, Sendable {
        public var revision: Int
        public var rejected: [Rejection]

        public struct Rejection: Codable, Sendable {
            public var id: String
            public var reason: String
        }
    }

    public struct ShareSummary: Codable, Sendable {
        public var id: String
        public var role: String
        public var revision: Int
        public var revoked: Bool
    }

    public struct ShareCreated: Codable, Sendable {
        public var shareId: String
        public var code: String
        public var revision: Int
    }

    public struct ShareContents: Codable, Sendable {
        public var share: ShareSummary
        public var revision: Int
        public var documents: [Document]
    }

    // MARK: - Account

    public func register() async throws -> Registration {
        try await call("api/v1/account", method: "POST", token: nil, body: Optional<Empty>.none)
    }

    public func recover(code: String) async throws -> Registration {
        try await call("api/v1/account/recover", method: "POST", token: nil,
                       body: ["code": code])
    }

    public func newRecoveryCode(token: String) async throws -> String {
        struct Response: Codable { var recoveryCode: String }
        let response: Response = try await call("api/v1/account", method: "PATCH",
                                                token: token, body: Optional<Empty>.none)
        return response.recoveryCode
    }

    public func deleteEverything(token: String) async throws {
        struct Response: Codable { var deleted: Bool }
        let _: Response = try await call("api/v1/account", method: "DELETE",
                                         token: token, body: Optional<Empty>.none)
    }

    // MARK: - Backup

    public func pull(token: String, since: Int) async throws -> Pull {
        try await call("api/v1/sync?since=\(since)", method: "GET", token: token,
                       body: Optional<Empty>.none)
    }

    public func push(token: String, documents: [Document]) async throws -> PushResult {
        try await call("api/v1/sync", method: "POST", token: token,
                       body: ["documents": documents])
    }

    // MARK: - Shares

    public func createShare(token: String, documents: [Document]) async throws -> ShareCreated {
        try await call("api/v1/shares", method: "POST", token: token,
                       body: ["documents": documents])
    }

    public func join(token: String, code: String) async throws -> ShareContents {
        try await call("api/v1/shares/join", method: "POST", token: token, body: ["code": code])
    }

    public func pullShare(token: String, shareId: String, since: Int) async throws -> ShareContents {
        try await call("api/v1/shares/\(shareId)/sync?since=\(since)", method: "GET",
                       token: token, body: Optional<Empty>.none)
    }

    public func pushShare(token: String, shareId: String, documents: [Document]) async throws -> PushResult {
        try await call("api/v1/shares/\(shareId)/sync", method: "POST", token: token,
                       body: ["documents": documents])
    }

    public func rotateCode(token: String, shareId: String) async throws -> String {
        struct Response: Codable { var code: String }
        let response: Response = try await call("api/v1/shares/\(shareId)/sync", method: "PATCH",
                                                token: token, body: ["action": "rotate"])
        return response.code
    }

    public func revokeShare(token: String, shareId: String) async throws {
        struct Response: Codable { var revoked: Bool }
        let _: Response = try await call("api/v1/shares/\(shareId)/sync", method: "PATCH",
                                         token: token, body: ["action": "revoke"])
    }

    // MARK: - Transport

    private struct Empty: Codable {}

    private func call<Body: Encodable, Response: Decodable>(
        _ path: String, method: String, token: String?, body: Body?
    ) async throws -> Response {
        guard let url = URL(string: path, relativeTo: baseURL) else { throw Failure.malformed }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw Failure.offline
        }

        guard let http = response as? HTTPURLResponse else { throw Failure.malformed }
        switch http.statusCode {
        case 200...299:
            guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
                throw Failure.malformed
            }
            return decoded
        case 404:
            throw Failure.notFound
        case 429:
            let retry = Int(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 60
            throw Failure.rateLimited(retryAfter: retry)
        default:
            throw Failure.server(status: http.statusCode)
        }
    }
}
