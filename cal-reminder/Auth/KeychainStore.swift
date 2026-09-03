import Foundation
import Security

/// Persists the OAuth refresh token securely (RNF-05: never in plaintext on disk).
/// Wraps Keychain Services (the security boundary) so it can be faked in tests.
protocol TokenStoring {
    func refreshToken() -> String?
    func setRefreshToken(_ token: String?)
}

final class KeychainStore: TokenStoring {
    /// The legacy, unscoped Keychain account name — used by the single-account build and
    /// read once more by `LegacyAccountMigration` (TDR-005).
    static let legacyAccount = "google-refresh-token"

    private let service: String
    private let account: String

    init(service: String = "com.cal-reminder.auth", account: String = KeychainStore.legacyAccount) {
        self.service = service
        self.account = account
    }

    /// The per-Account Keychain entry name (TDR-005): `google-refresh-token#<accountId>`.
    static func accountScopedKey(_ accountId: String) -> String {
        "\(legacyAccount)#\(accountId)"
    }

    func refreshToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func setRefreshToken(_ token: String?) {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(baseQuery as CFDictionary)

        guard let token else { return }

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = Data(token.utf8)
        SecItemAdd(addQuery as CFDictionary, nil)
    }
}
