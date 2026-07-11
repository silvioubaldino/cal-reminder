import Foundation
import Security

/// Persists the OAuth refresh token securely (RNF-05: never in plaintext on disk).
/// Wraps Keychain Services (the security boundary) so it can be faked in tests.
protocol TokenStoring {
    func refreshToken() -> String?
    func setRefreshToken(_ token: String?)
}

final class KeychainStore: TokenStoring {
    private let service: String
    private let account = "google-refresh-token"

    init(service: String = "com.cal-reminder.auth") {
        self.service = service
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
