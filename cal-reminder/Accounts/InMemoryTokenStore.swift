import Foundation

/// In-memory `TokenStoring`, used for the provisional connect step of `addAccount`/
/// `reconnect` — before the resolved identity's token is committed to the real,
/// Account-scoped Keychain store (AYD-007) — and to seed a provisional identity check with
/// an already-known token (`LegacyAccountMigration`).
final class InMemoryTokenStore: TokenStoring {
    private var token: String?

    init(token: String? = nil) {
        self.token = token
    }

    func refreshToken() -> String? { token }
    func setRefreshToken(_ token: String?) { self.token = token }
}
