import Foundation

/// Migrates the pre-multi-account Keychain token + Calendar selection into the new
/// per-Account storage, on the first `restore()` after upgrading past the single-account
/// build (TDR-005). A no-op once any Account is already registered.
protocol LegacyAccountMigrating {
    func migrateIfNeeded(accountStore: AccountStoring) async
}

struct LegacyAccountMigration: LegacyAccountMigrating {
    /// Reads/clears the legacy, unscoped Keychain entry.
    let legacyTokenStore: TokenStoring
    /// Builds the real, Account-scoped Keychain store the token is re-keyed into.
    let scopedTokenStore: (String) -> TokenStoring
    /// Builds the real, Account-scoped Calendar-selection store the legacy selection is
    /// copied into.
    let scopedCalendarSelectionStore: (String) -> CalendarSelectionStoring
    /// Resolves identity from a token without a fresh OAuth round-trip — the legacy token
    /// is already known, only its validity and owner need confirming.
    let provisionalAuthFactory: (TokenStoring) -> AccountAuthenticating
    let defaults: UserDefaults

    init(
        legacyTokenStore: TokenStoring = KeychainStore(),
        scopedTokenStore: @escaping (String) -> TokenStoring = { KeychainStore(account: KeychainStore.accountScopedKey($0)) },
        scopedCalendarSelectionStore: @escaping (String) -> CalendarSelectionStoring = { UserDefaultsCalendarSelectionStore(accountId: $0) },
        provisionalAuthFactory: @escaping (TokenStoring) -> AccountAuthenticating,
        defaults: UserDefaults = .standard
    ) {
        self.legacyTokenStore = legacyTokenStore
        self.scopedTokenStore = scopedTokenStore
        self.scopedCalendarSelectionStore = scopedCalendarSelectionStore
        self.provisionalAuthFactory = provisionalAuthFactory
        self.defaults = defaults
    }

    func migrateIfNeeded(accountStore: AccountStoring) async {
        guard accountStore.accounts.isEmpty else { return }
        guard let token = legacyTokenStore.refreshToken() else { return }

        let auth = provisionalAuthFactory(InMemoryTokenStore(token: token))
        do {
            let account = try await auth.identity()

            scopedTokenStore(account.id).setRefreshToken(token)
            if let legacySelection = legacySelectedCalendarIds() {
                scopedCalendarSelectionStore(account.id).selectedCalendarIds = legacySelection
            }
            accountStore.accounts = [account]

            // Only clear the legacy keys once everything above has landed — a crash or
            // termination mid-migration just means this whole method runs again next launch.
            legacyTokenStore.setRefreshToken(nil)
            defaults.removeObject(forKey: UserDefaultsCalendarSelectionStore.legacyKey)
        } catch AuthError.refreshTokenRevoked {
            // The session was already dead — nothing to migrate, but the dead token
            // shouldn't linger either (SPEC-010's existing rule, applied here too).
            legacyTokenStore.setRefreshToken(nil)
        } catch {
            // Network or transient failure: leave everything untouched and retry on the
            // next restore() — a valid token must never be discarded over a blip (RNF-04).
            print("[LegacyAccountMigration] deferred: \(error)")
        }
    }

    private func legacySelectedCalendarIds() -> Set<String>? {
        guard let stored = defaults.array(forKey: UserDefaultsCalendarSelectionStore.legacyKey) as? [String] else { return nil }
        return Set(stored)
    }
}
