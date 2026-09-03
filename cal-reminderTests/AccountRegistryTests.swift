import XCTest
@testable import cal_reminder

private final class FakeAccountStore: AccountStoring {
    var accounts: [Account] = []
}

private struct NoOpLegacyMigration: LegacyAccountMigrating {
    func migrateIfNeeded(accountStore: AccountStoring) async {}
}

private final class FakeTokenStore: TokenStoring {
    private var token: String?
    init(token: String? = nil) { self.token = token }
    func refreshToken() -> String? { token }
    func setRefreshToken(_ token: String?) { self.token = token }
}

private final class FakeCalendarSelectionStore: CalendarSelectionStoring {
    var selectedCalendarIds: Set<String>?
}

private final class FakeAccountAuthenticating: AccountAuthenticating {
    var isConnected = true
    var connectError: Error?
    var identityResult: Result<Account, Error>
    var tokenToIssueOnConnect: String?
    private(set) var connectLoginHints: [String?] = []
    private(set) var identityCallCount = 0
    private var tokenStore: TokenStoring?

    init(identityResult: Result<Account, Error>, tokenToIssueOnConnect: String? = "fresh-token") {
        self.identityResult = identityResult
        self.tokenToIssueOnConnect = tokenToIssueOnConnect
    }

    func attach(tokenStore: TokenStoring) {
        self.tokenStore = tokenStore
    }

    func connect(loginHint: String?) async throws {
        connectLoginHints.append(loginHint)
        if let connectError { throw connectError }
        tokenStore?.setRefreshToken(tokenToIssueOnConnect)
    }

    func identity() async throws -> Account {
        identityCallCount += 1
        return try identityResult.get()
    }

    func disconnect() async {}
}

private final class FakeCalendarServicing: CalendarServicing {
    var triggers: [Trigger] = []
    var pollError: Error?
    var calendars: [CalendarInfo] = []
    private(set) var pollCallCount = 0

    func poll(fullResync: Bool) async throws -> [Trigger] {
        pollCallCount += 1
        if let pollError { throw pollError }
        return triggers
    }

    func availableCalendars() async throws -> [CalendarInfo] {
        calendars
    }
}

private final class AccountRegistryHarness {
    let accountStore = FakeAccountStore()
    var legacyMigration: LegacyAccountMigrating = NoOpLegacyMigration()
    var provisionalAuth: FakeAccountAuthenticating?

    private var tokenStores: [String: FakeTokenStore] = [:]
    private var selectionStores: [String: FakeCalendarSelectionStore] = [:]
    private var calendarServices: [String: FakeCalendarServicing] = [:]
    private var authServices: [String: FakeAccountAuthenticating] = [:]

    func tokenStore(for accountId: String) -> FakeTokenStore {
        if let existing = tokenStores[accountId] { return existing }
        let store = FakeTokenStore()
        tokenStores[accountId] = store
        return store
    }

    func selectionStore(for accountId: String) -> FakeCalendarSelectionStore {
        if let existing = selectionStores[accountId] { return existing }
        let store = FakeCalendarSelectionStore()
        selectionStores[accountId] = store
        return store
    }

    func calendarService(for accountId: String) -> FakeCalendarServicing {
        if let existing = calendarServices[accountId] { return existing }
        let service = FakeCalendarServicing()
        calendarServices[accountId] = service
        return service
    }

    func authService(for account: Account) -> FakeAccountAuthenticating {
        if let existing = authServices[account.id] { return existing }
        let auth = FakeAccountAuthenticating(identityResult: .success(account))
        authServices[account.id] = auth
        return auth
    }

    func makeRegistry() -> AccountRegistry {
        let factories = AccountSessionFactories(
            scopedTokenStore: { [self] in tokenStore(for: $0) },
            scopedCalendarSelectionStore: { [self] in selectionStore(for: $0) },
            provisionalAuthFactory: { [self] tokenStore in
                let auth = provisionalAuth ?? FakeAccountAuthenticating(identityResult: .failure(AuthError.notConnected))
                auth.attach(tokenStore: tokenStore)
                return auth
            },
            sessionFactory: { [self] account, _, _ in (authService(for: account), calendarService(for: account.id)) }
        )
        return AccountRegistry(accountStore: accountStore, legacyMigration: legacyMigration, factories: factories)
    }
}

private func account(_ id: String, label: String) -> Account {
    Account(id: id, provider: .google, label: label)
}

private func trigger(id: String, minutesFromNow: TimeInterval = 5) -> Trigger {
    let start = Date().addingTimeInterval(minutesFromNow * 60)
    return Trigger(id: id, eventTitle: "Event", startDate: start, fireDate: start, minutesBefore: Int(minutesFromNow))
}

final class AccountRegistryTests: XCTestCase {
    private let accountA = account("google:a", label: "a@example.com")
    private let accountB = account("google:b", label: "b@example.com")

    func test_pollMergesTriggersFromBothAccounts() async {
        let harness = AccountRegistryHarness()
        harness.accountStore.accounts = [accountA, accountB]
        harness.calendarService(for: "google:a").triggers = [trigger(id: "google:a#cal#evt#5")]
        harness.calendarService(for: "google:b").triggers = [trigger(id: "google:b#cal#evt#5")]
        let registry = harness.makeRegistry()
        await registry.restore()

        let result = await registry.poll(fullResync: false)

        XCTAssertEqual(Set(result.triggers.map(\.id)), ["google:a#cal#evt#5", "google:b#cal#evt#5"])
        XCTAssertTrue(result.anyAccountSucceeded)
    }

    func test_sameCalendarIdSharedByTwoAccountsDoesNotCollide() async {
        let harness = AccountRegistryHarness()
        harness.accountStore.accounts = [accountA, accountB]
        harness.calendarService(for: "google:a").triggers = [trigger(id: "google:a#shared@group.calendar.google.com#evt1#10")]
        harness.calendarService(for: "google:b").triggers = [trigger(id: "google:b#shared@group.calendar.google.com#evt1#10")]
        let registry = harness.makeRegistry()
        await registry.restore()

        let result = await registry.poll(fullResync: false)

        XCTAssertEqual(result.triggers.count, 2)
        XCTAssertEqual(Set(result.triggers.map(\.id)).count, 2)
    }

    func test_oneAccountsRevokedSessionDoesNotAffectTheOther() async {
        let harness = AccountRegistryHarness()
        harness.accountStore.accounts = [accountA, accountB]
        harness.calendarService(for: "google:a").triggers = [trigger(id: "google:a#cal#evt#5")]
        harness.calendarService(for: "google:b").pollError = AuthError.refreshTokenRevoked
        let registry = harness.makeRegistry()
        await registry.restore()

        let result = await registry.poll(fullResync: false)

        XCTAssertEqual(result.triggers.map(\.id), ["google:a#cal#evt#5"])
        XCTAssertEqual(registry.sessions.first { $0.id == "google:a" }?.connectionStatus, .connected)
        XCTAssertEqual(registry.sessions.first { $0.id == "google:b" }?.connectionStatus, .needsReauth)
    }

    func test_oneAccountsNetworkFailureDoesNotAffectTheOther() async {
        let harness = AccountRegistryHarness()
        harness.accountStore.accounts = [accountA, accountB]
        harness.calendarService(for: "google:a").triggers = [trigger(id: "google:a#cal#evt#5")]
        harness.calendarService(for: "google:b").pollError = URLError(.notConnectedToInternet)
        let registry = harness.makeRegistry()
        await registry.restore()
        let statusBefore = registry.sessions.first { $0.id == "google:b" }?.connectionStatus

        let result = await registry.poll(fullResync: false)

        XCTAssertEqual(result.triggers.map(\.id), ["google:a#cal#evt#5"])
        XCTAssertEqual(registry.sessions.first { $0.id == "google:a" }?.connectionStatus, .connected)
        XCTAssertEqual(registry.sessions.first { $0.id == "google:b" }?.connectionStatus, statusBefore, "a transient failure must not change the status (RNF-04)")
    }

    func test_pollReportsNoAccountSucceededOnATotalOutage() async {
        let harness = AccountRegistryHarness()
        harness.accountStore.accounts = [accountA, accountB]
        harness.calendarService(for: "google:a").pollError = URLError(.notConnectedToInternet)
        harness.calendarService(for: "google:b").pollError = URLError(.notConnectedToInternet)
        let registry = harness.makeRegistry()
        await registry.restore()

        let result = await registry.poll(fullResync: true)

        XCTAssertTrue(result.triggers.isEmpty)
        XCTAssertFalse(result.anyAccountSucceeded)
    }

    func test_addAccountRegistersANewAccountWithoutDisturbingTheFirst() async throws {
        let harness = AccountRegistryHarness()
        harness.accountStore.accounts = [accountA]
        harness.tokenStore(for: "google:a").setRefreshToken("token-a")
        harness.selectionStore(for: "google:a").selectedCalendarIds = ["Cal1"]
        let registry = harness.makeRegistry()
        await registry.restore()
        harness.provisionalAuth = FakeAccountAuthenticating(identityResult: .success(accountB), tokenToIssueOnConnect: "token-b")

        let resolved = try await registry.addAccount(provider: .google)

        XCTAssertEqual(resolved, accountB)
        XCTAssertEqual(registry.sessions.map(\.id).sorted(), ["google:a", "google:b"])
        XCTAssertEqual(harness.accountStore.accounts.map(\.id).sorted(), ["google:a", "google:b"])
        XCTAssertEqual(harness.tokenStore(for: "google:a").refreshToken(), "token-a", "A's token must be untouched")
        XCTAssertEqual(harness.selectionStore(for: "google:a").selectedCalendarIds, ["Cal1"], "A's selection must be untouched")
        XCTAssertEqual(harness.tokenStore(for: "google:b").refreshToken(), "token-b")
    }

    func test_addAccountResolvingAnAlreadyConnectedIdentityUpdatesInsteadOfDuplicating() async throws {
        let harness = AccountRegistryHarness()
        harness.accountStore.accounts = [accountA]
        harness.tokenStore(for: "google:a").setRefreshToken("old-token")
        let registry = harness.makeRegistry()
        await registry.restore()
        harness.provisionalAuth = FakeAccountAuthenticating(identityResult: .success(accountA), tokenToIssueOnConnect: "new-token")

        _ = try await registry.addAccount(provider: .google)

        XCTAssertEqual(registry.sessions.map(\.id), ["google:a"], "must not duplicate the session")
        XCTAssertEqual(harness.accountStore.accounts.count, 1)
        XCTAssertEqual(harness.tokenStore(for: "google:a").refreshToken(), "new-token")
    }

    func test_reconnectResolvingADifferentIdentityRegistersThatIdentityNotTheOriginal() async throws {
        let harness = AccountRegistryHarness()
        harness.accountStore.accounts = [accountA]
        harness.tokenStore(for: "google:a").setRefreshToken("token-a")
        let registry = harness.makeRegistry()
        await registry.restore()
        let accountC = account("google:c", label: "c@example.com")
        harness.provisionalAuth = FakeAccountAuthenticating(identityResult: .success(accountC), tokenToIssueOnConnect: "token-c")

        try await registry.reconnect(accountId: "google:a")

        XCTAssertEqual(registry.sessions.map(\.id).sorted(), ["google:a", "google:c"])
        XCTAssertEqual(harness.tokenStore(for: "google:a").refreshToken(), "token-a", "A's token must be untouched")
        XCTAssertEqual(harness.tokenStore(for: "google:c").refreshToken(), "token-c")
    }

    func test_reconnectUsesTheExistingAccountsLabelAsLoginHint() async throws {
        let harness = AccountRegistryHarness()
        harness.accountStore.accounts = [accountA]
        let registry = harness.makeRegistry()
        await registry.restore()
        let provisional = FakeAccountAuthenticating(identityResult: .success(accountA))
        harness.provisionalAuth = provisional

        try await registry.reconnect(accountId: "google:a")

        XCTAssertEqual(provisional.connectLoginHints, ["a@example.com"])
    }

    func test_signOutRemovesOnlyThatAccountsStoredData() async {
        let harness = AccountRegistryHarness()
        harness.accountStore.accounts = [accountA, accountB]
        harness.tokenStore(for: "google:a").setRefreshToken("token-a")
        harness.tokenStore(for: "google:b").setRefreshToken("token-b")
        harness.selectionStore(for: "google:a").selectedCalendarIds = ["Cal1"]
        let registry = harness.makeRegistry()
        await registry.restore()

        await registry.signOut(accountId: "google:a")

        XCTAssertEqual(registry.sessions.map(\.id), ["google:b"])
        XCTAssertEqual(harness.accountStore.accounts.map(\.id), ["google:b"])
        XCTAssertNil(harness.tokenStore(for: "google:a").refreshToken())
        XCTAssertNil(harness.selectionStore(for: "google:a").selectedCalendarIds)
        XCTAssertEqual(harness.tokenStore(for: "google:b").refreshToken(), "token-b", "B must be untouched")
    }

    func test_verifySessionsMovesEachSessionToConnectedOrNeedsReauth() async {
        let harness = AccountRegistryHarness()
        harness.accountStore.accounts = [accountA, accountB]
        harness.authService(for: accountA).identityResult = .success(accountA)
        harness.authService(for: accountB).identityResult = .failure(AuthError.refreshTokenRevoked)
        let registry = harness.makeRegistry()
        await registry.restore()
        XCTAssertEqual(registry.sessions.map(\.connectionStatus), [.connecting, .connecting])

        await registry.verifySessions()

        XCTAssertEqual(registry.sessions.first { $0.id == "google:a" }?.connectionStatus, .connected)
        XCTAssertEqual(registry.sessions.first { $0.id == "google:b" }?.connectionStatus, .needsReauth)
    }

    private func makeMigration(
        legacyTokenStore: TokenStoring,
        scopedTokenStore: @escaping (String) -> TokenStoring = { _ in FakeTokenStore() },
        scopedCalendarSelectionStore: @escaping (String) -> CalendarSelectionStoring = { _ in FakeCalendarSelectionStore() },
        provisionalAuthFactory: @escaping (TokenStoring) -> AccountAuthenticating,
        defaults: UserDefaults
    ) -> LegacyAccountMigration {
        LegacyAccountMigration(
            legacyTokenStore: legacyTokenStore,
            scopedTokenStore: scopedTokenStore,
            scopedCalendarSelectionStore: scopedCalendarSelectionStore,
            provisionalAuthFactory: provisionalAuthFactory,
            defaults: defaults
        )
    }

    private func uniqueDefaults() -> UserDefaults {
        UserDefaults(suiteName: "AccountRegistryTests.\(UUID().uuidString)")!
    }

    func test_legacyMigrationSucceedsAndMovesTokenAndSelectionToTheScopedKeys() async {
        let defaults = uniqueDefaults()
        defaults.set(["Cal1", "Cal2"], forKey: UserDefaultsCalendarSelectionStore.legacyKey)
        let legacyTokenStore = FakeTokenStore(token: "legacy-token")
        let scopedToken = FakeTokenStore()
        let scopedSelection = FakeCalendarSelectionStore()
        let migratedAccount = account("google:migrated", label: "migrated@example.com")
        let accountStore = FakeAccountStore()
        let migration = makeMigration(
            legacyTokenStore: legacyTokenStore,
            scopedTokenStore: { _ in scopedToken },
            scopedCalendarSelectionStore: { _ in scopedSelection },
            provisionalAuthFactory: { _ in FakeAccountAuthenticating(identityResult: .success(migratedAccount)) },
            defaults: defaults
        )

        await migration.migrateIfNeeded(accountStore: accountStore)

        XCTAssertEqual(accountStore.accounts, [migratedAccount])
        XCTAssertEqual(scopedToken.refreshToken(), "legacy-token")
        XCTAssertEqual(scopedSelection.selectedCalendarIds, ["Cal1", "Cal2"])
        XCTAssertNil(legacyTokenStore.refreshToken())
        XCTAssertNil(defaults.array(forKey: UserDefaultsCalendarSelectionStore.legacyKey))
    }

    func test_legacyMigrationRevokedTokenClearsLegacyKeyWithoutRegisteringAnAccount() async {
        let legacyTokenStore = FakeTokenStore(token: "dead-token")
        let accountStore = FakeAccountStore()
        let migration = makeMigration(
            legacyTokenStore: legacyTokenStore,
            provisionalAuthFactory: { _ in FakeAccountAuthenticating(identityResult: .failure(AuthError.refreshTokenRevoked)) },
            defaults: uniqueDefaults()
        )

        await migration.migrateIfNeeded(accountStore: accountStore)

        XCTAssertTrue(accountStore.accounts.isEmpty)
        XCTAssertNil(legacyTokenStore.refreshToken())
    }

    func test_legacyMigrationNetworkFailureDefersToNextLaunch() async {
        let legacyTokenStore = FakeTokenStore(token: "legacy-token")
        let accountStore = FakeAccountStore()
        let migration = makeMigration(
            legacyTokenStore: legacyTokenStore,
            provisionalAuthFactory: { _ in FakeAccountAuthenticating(identityResult: .failure(URLError(.notConnectedToInternet))) },
            defaults: uniqueDefaults()
        )

        await migration.migrateIfNeeded(accountStore: accountStore)

        XCTAssertTrue(accountStore.accounts.isEmpty)
        XCTAssertEqual(legacyTokenStore.refreshToken(), "legacy-token")
    }

    func test_legacyMigrationIsANoOpWhenAnAccountAlreadyExists() async {
        let legacyTokenStore = FakeTokenStore(token: "legacy-token")
        let accountStore = FakeAccountStore()
        accountStore.accounts = [account("google:existing", label: "existing@example.com")]
        let migration = makeMigration(
            legacyTokenStore: legacyTokenStore,
            provisionalAuthFactory: { _ in FakeAccountAuthenticating(identityResult: .failure(AuthError.notConnected)) },
            defaults: uniqueDefaults()
        )

        await migration.migrateIfNeeded(accountStore: accountStore)

        XCTAssertEqual(accountStore.accounts.count, 1)
        XCTAssertEqual(legacyTokenStore.refreshToken(), "legacy-token")
    }
}
