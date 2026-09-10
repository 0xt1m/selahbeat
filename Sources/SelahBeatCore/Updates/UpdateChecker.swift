import Foundation
import Observation
import OSLog

/// Checks GitHub Releases for a newer version on launch.
///
/// This is the dependency-free half of the update story and works on every
/// platform: it tells the user a release exists and links to it. Sparkle, when
/// linked into the macOS target, upgrades that to download-and-install in one
/// click. Both silently do nothing when offline — a metronome must never
/// interrupt a service with a network error.
@MainActor
@Observable
public final class UpdateChecker {
    public struct Release: Sendable, Equatable {
        public let version: String
        public let url: URL
        public let notes: String?
        public let publishedAt: Date?
    }

    public private(set) var availableUpdate: Release?
    public private(set) var isChecking = false
    public private(set) var lastCheck: Date?

    private let repo: String
    private let currentVersion: String
    private let session: URLSession
    private let log = Logger(subsystem: "app.selahbeat", category: "updates")

    /// Versions the user has explicitly dismissed.
    private var skippedVersions: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "app.selahbeat.skippedVersions") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "app.selahbeat.skippedVersions") }
    }

    public init(
        repo: String = "0xt1m/selahbeat",
        currentVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    ) {
        self.repo = repo
        self.currentVersion = currentVersion

        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 10
        self.session = URLSession(configuration: config)
    }

    public func check() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false; lastCheck = Date() }

        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }

            struct Payload: Decodable {
                let tag_name: String
                let html_url: String
                let body: String?
                let published_at: String?
                let draft: Bool?
                let prerelease: Bool?
            }
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            guard payload.draft != true, payload.prerelease != true else { return }

            let latest = payload.tag_name.hasPrefix("v")
                ? String(payload.tag_name.dropFirst())
                : payload.tag_name

            guard Self.isNewer(latest, than: currentVersion),
                  !skippedVersions.contains(latest),
                  let releaseURL = URL(string: payload.html_url) else { return }

            availableUpdate = Release(
                version: latest,
                url: releaseURL,
                notes: payload.body,
                publishedAt: payload.published_at.flatMap { ISO8601DateFormatter().date(from: $0) }
            )
            log.info("Update available: \(latest, privacy: .public)")
        } catch {
            // Offline is the normal case, not an error worth showing.
            log.debug("Update check skipped: \(error.localizedDescription)")
        }
    }

    public func skip(_ release: Release) {
        skippedVersions.insert(release.version)
        availableUpdate = nil
    }

    public func dismiss() {
        availableUpdate = nil
    }

    /// Numeric component-wise comparison, so 0.10.0 correctly beats 0.9.0
    /// (a plain string compare would get that backwards).
    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        let b = current.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let lhs = i < a.count ? a[i] : 0
            let rhs = i < b.count ? b[i] : 0
            if lhs != rhs { return lhs > rhs }
        }
        return false
    }
}
