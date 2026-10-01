import Foundation
import Security
import OSLog

/// Who this device is to the server, with no login.
///
/// The account id and its secret live in the Keychain rather than in the
/// app's own files, because the Keychain survives the app being deleted and
/// reinstalled - which is the whole problem this exists to solve. On a new
/// phone, the recovery code is the way back.
public struct SyncCredentials: Codable, Sendable, Equatable {
    public var accountId: String
    public var deviceId: String
    public var secret: String

    public var token: String { "\(deviceId).\(secret)" }
}

@MainActor
public final class SyncIdentity {
    private let service = "app.selahbeat.sync"
    private let account = "credentials"
    private let log = Logger(subsystem: "app.selahbeat", category: "sync")

    public private(set) var credentials: SyncCredentials?

    public init() {
        credentials = load()
    }

    public var isRegistered: Bool { credentials != nil }

    public func store(_ credentials: SyncCredentials) {
        self.credentials = credentials
        guard let data = try? JSONEncoder().encode(credentials) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)

        var insert = query
        insert[kSecValueData as String] = data
        // Not synchronised to iCloud Keychain and not available until the
        // device has been unlocked once: a metronome never syncs in the
        // background before its owner has opened the phone.
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(insert as CFDictionary, nil)
        if status != errSecSuccess {
            log.error("Could not store credentials: \(status)")
        }
    }

    public func forget() {
        credentials = nil
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ] as CFDictionary)
    }

    private func load() -> SyncCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(SyncCredentials.self, from: data)
    }
}
