import Foundation

protocol LegacyAccountMigrating {
    func migrateIfNeeded(accountStore: AccountStoring) async
}

struct LegacyAccountMigration: LegacyAccountMigrating {
    let legacyTokenStore: TokenStoring
    let scopedTokenStore: (String) -> TokenStoring
    let scopedCalendarSelectionStore: (String) -> CalendarSelectionStoring
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

            legacyTokenStore.setRefreshToken(nil)
            defaults.removeObject(forKey: UserDefaultsCalendarSelectionStore.legacyKey)
        } catch AuthError.refreshTokenRevoked {
            legacyTokenStore.setRefreshToken(nil)
        } catch {
            print("[LegacyAccountMigration] deferred: \(error)")
        }
    }

    private func legacySelectedCalendarIds() -> Set<String>? {
        guard let stored = defaults.array(forKey: UserDefaultsCalendarSelectionStore.legacyKey) as? [String] else { return nil }
        return Set(stored)
    }
}
