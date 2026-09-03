import Foundation

/// One connected Account's live state, as read by `AppCoordinator` to build `AppState`
/// (RF-14). A snapshot — mutated only through `AccountRegistry`'s own methods.
struct AccountSession: Identifiable {
    let account: Account
    var connectionStatus: ConnectionStatus
    var calendars: [CalendarInfo] = []

    var id: String { account.id }
}

/// Owns every connected Account's session and is what `AppCoordinator` talks to instead of
/// a single app-wide `auth`/`calendar` pair (AYD-007).
protocol AccountsManaging: AnyObject {
    /// Ordered like `AccountStore`; each session's `connectionStatus`/`calendars` reflect
    /// the last `restore()`/`verifySessions()`/`poll()` call.
    var sessions: [AccountSession] { get }

    /// Loads persisted Accounts (running the legacy single-account migration first) and
    /// builds their sessions. Called once, at launch.
    func restore() async
    /// Re-verifies every session's connection (startup/reconnect window).
    func verifySessions() async
    /// Starts the OAuth flow for a brand-new Account. Updates the existing session instead
    /// of duplicating one if the resolved identity is already connected.
    func addAccount(provider: AccountProvider) async throws -> Account
    /// Re-authorizes one Account, pre-selecting it in Google's account chooser. If the
    /// resolved identity turns out to be a *different* Account, that Account is
    /// registered/updated instead — `accountId`'s stored token is never touched in that case.
    func reconnect(accountId: String) async throws
    /// Removes one Account entirely: its Keychain entry, its Calendar selection, and its
    /// session. The other Accounts are untouched.
    func signOut(accountId: String) async
    /// Fans a Poll out across every session, merging their Triggers. A session's failure
    /// only updates that session's `connectionStatus` — the others' Triggers still return
    /// (mirrors how `CalendarService.poll()` already isolates a single Calendar's failure).
    /// `anyAccountSucceeded` tells the caller whether *any* session's fetch actually
    /// completed this round — a full resync (SPEC-013) must not wipe the Scheduler's armed
    /// set on a total outage across every Account (RNF-04), the same guarantee the
    /// single-account build made by never reaching `cancelAll()` when the whole Poll threw.
    func poll(fullResync: Bool) async -> (triggers: [Trigger], anyAccountSucceeded: Bool)
}

/// Not actor-isolated, like `CalendarService` — safe because `AppCoordinator` (its only
/// caller) is itself `@MainActor` and never calls into this concurrently.
final class AccountRegistry: AccountsManaging {
    private struct Live {
        let auth: AccountAuthenticating
        let calendar: CalendarServicing
    }

    private let accountStore: AccountStoring
    private let legacyMigration: LegacyAccountMigrating
    private let scopedTokenStore: (String) -> TokenStoring
    private let scopedCalendarSelectionStore: (String) -> CalendarSelectionStoring
    private let provisionalAuthFactory: (TokenStoring) -> AccountAuthenticating
    /// Builds the live `auth`/`calendar` pair for an Account on top of its already-scoped
    /// token + Calendar-selection stores.
    private let sessionFactory: (Account, TokenStoring, CalendarSelectionStoring) -> (auth: AccountAuthenticating, calendar: CalendarServicing)

    private var accounts: [Account] = []
    private var live: [String: Live] = [:]
    private var statuses: [String: ConnectionStatus] = [:]
    private var calendarsByAccount: [String: [CalendarInfo]] = [:]

    var sessions: [AccountSession] {
        accounts.map {
            AccountSession(
                account: $0,
                connectionStatus: statuses[$0.id] ?? .disconnected,
                calendars: calendarsByAccount[$0.id] ?? []
            )
        }
    }

    init(
        accountStore: AccountStoring,
        legacyMigration: LegacyAccountMigrating,
        scopedTokenStore: @escaping (String) -> TokenStoring,
        scopedCalendarSelectionStore: @escaping (String) -> CalendarSelectionStoring,
        provisionalAuthFactory: @escaping (TokenStoring) -> AccountAuthenticating,
        sessionFactory: @escaping (Account, TokenStoring, CalendarSelectionStoring) -> (auth: AccountAuthenticating, calendar: CalendarServicing)
    ) {
        self.accountStore = accountStore
        self.legacyMigration = legacyMigration
        self.scopedTokenStore = scopedTokenStore
        self.scopedCalendarSelectionStore = scopedCalendarSelectionStore
        self.provisionalAuthFactory = provisionalAuthFactory
        self.sessionFactory = sessionFactory
    }

    func restore() async {
        await legacyMigration.migrateIfNeeded(accountStore: accountStore)
        accounts = accountStore.accounts
        for account in accounts {
            statuses[account.id] = .connecting
            live[account.id] = buildLive(for: account)
        }
    }

    func verifySessions() async {
        for account in accounts {
            guard let session = live[account.id] else { continue }
            do {
                _ = try await session.auth.identity()
                statuses[account.id] = .connected
            } catch AuthError.refreshTokenRevoked {
                statuses[account.id] = .needsReauth
            } catch {
                print("[AccountRegistry] verify failed for \(account.id): \(error)")
            }
        }
    }

    /// `provider` is currently always `.google` — kept explicit so a future non-Google
    /// source doesn't need this signature to change (AYD-007 "Open questions").
    func addAccount(provider: AccountProvider) async throws -> Account {
        try await connectAndCommit(loginHint: nil)
    }

    func reconnect(accountId: String) async throws {
        let loginHint = accounts.first { $0.id == accountId }?.label
        _ = try await connectAndCommit(loginHint: loginHint)
    }

    func signOut(accountId: String) async {
        scopedTokenStore(accountId).setRefreshToken(nil)
        scopedCalendarSelectionStore(accountId).selectedCalendarIds = nil
        accounts.removeAll { $0.id == accountId }
        live.removeValue(forKey: accountId)
        statuses.removeValue(forKey: accountId)
        calendarsByAccount.removeValue(forKey: accountId)
        accountStore.accounts = accounts
    }

    func poll(fullResync: Bool) async -> (triggers: [Trigger], anyAccountSucceeded: Bool) {
        var triggers: [Trigger] = []
        var anySucceeded = false
        for account in accounts {
            guard let session = live[account.id] else { continue }
            do {
                triggers += try await session.calendar.poll(fullResync: fullResync)
                anySucceeded = true
                statuses[account.id] = .connected
                calendarsByAccount[account.id] = (try? await session.calendar.availableCalendars()) ?? calendarsByAccount[account.id] ?? []
            } catch AuthError.refreshTokenRevoked {
                print("[AccountRegistry] poll: \(account.id) needs reauth")
                statuses[account.id] = .needsReauth
            } catch {
                // A single Account's transient failure must not drop the others' Triggers
                // (RNF-04) — leave its connectionStatus as-is and move on, mirroring how
                // CalendarService.poll() already isolates one Calendar's failure.
                print("[AccountRegistry] poll failed for \(account.id): \(error)")
            }
        }
        return (triggers, anySucceeded)
    }

    /// Resolves identity through a provisional, in-memory-token OAuth flow, then commits
    /// the result: writes the token to the resolved Account's real Keychain entry and
    /// upserts its session — updating an already-connected Account (same id) rather than
    /// duplicating it (AYD-007 "add Account" / "reconnect" flow).
    private func connectAndCommit(loginHint: String?) async throws -> Account {
        let provisionalToken = InMemoryTokenStore()
        let provisionalAuth = provisionalAuthFactory(provisionalToken)
        try await provisionalAuth.connect(loginHint: loginHint)
        let account = try await provisionalAuth.identity()

        scopedTokenStore(account.id).setRefreshToken(provisionalToken.refreshToken())

        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
        } else {
            accounts.append(account)
        }
        accountStore.accounts = accounts

        live[account.id] = buildLive(for: account)
        statuses[account.id] = .connected
        return account
    }

    private func buildLive(for account: Account) -> Live {
        let (auth, calendar) = sessionFactory(account, scopedTokenStore(account.id), scopedCalendarSelectionStore(account.id))
        return Live(auth: auth, calendar: calendar)
    }
}
