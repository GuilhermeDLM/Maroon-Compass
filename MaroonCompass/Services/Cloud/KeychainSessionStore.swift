import Foundation
import Security

/// Keeps the Supabase session in one Keychain item that never leaves this device: it is not
/// synchronized to iCloud Keychain and does not migrate through backups to another device.
struct KeychainSessionStore: AuthSessionStore {
    struct KeychainError: Error, Equatable {
        let status: OSStatus
    }

    private let service = "com.guilhermemachado.MaroonCompass.cloud-session"
    private let account = "supabase"

    private var itemQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false
        ]
    }

    func load() throws -> AuthSession? {
        var query = itemQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let session = try? JSONDecoder().decode(AuthSession.self, from: data) else {
                // An unreadable item can never become usable; remove it.
                try? clear()
                return nil
            }
            return session
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError(status: status)
        }
    }

    func save(_ session: AuthSession) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: try JSONEncoder().encode(session),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemUpdate(itemQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let item = itemQuery.merging(attributes) { _, new in new }
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    func clear() throws {
        let status = SecItemDelete(itemQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }

    /// Keychain items survive app deletion. The first launch of a fresh install removes a
    /// session left by an earlier install, so deleting the app also signs it out.
    static func removeSessionLeftByPreviousInstall(defaults: UserDefaults = .standard) {
        let marker = "cloudSessionKeychainInstallMarker.v1"
        guard !defaults.bool(forKey: marker) else { return }
        try? KeychainSessionStore().clear()
        defaults.set(true, forKey: marker)
    }
}

extension CloudServices {
    /// The app's cloud services, or nil when this build has no `SupabaseConfig.plist`
    /// (local mode). Created on first use.
    static let shared: CloudServices? = {
        guard let configuration = SupabaseConfiguration.fromBundle() else { return nil }
        KeychainSessionStore.removeSessionLeftByPreviousInstall()
        return CloudServices(
            configuration: configuration,
            transport: URLSessionTransport(),
            sessionStore: KeychainSessionStore()
        )
    }()
}
