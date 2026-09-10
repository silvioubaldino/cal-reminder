import Foundation

struct AccountSession: Identifiable {
    let account: Account
    var connectionStatus: ConnectionStatus
    var calendars: [CalendarInfo] = []

    var id: String { account.id }
}

protocol AccountsManaging: AnyObject {
    var sessions: [AccountSession] { get }

    func restore() async
    func verifySessions() async
    func addAccount(provider: AccountProvider) async throws -> Account
    func reconnect(accountId: String) async throws
    func signOut(accountId: String) async
    func poll(fullResync: Bool) async -> (triggers: [Trigger], authoritativeAccountIds: Set<String>)
}

struct AccountSessionFactories {
    let scopedTokenStore: (String) -> TokenStoring
    let scopedCalendarSelectionStore: (String) -> CalendarSelectionStoring
    let provisionalAuthFactory: (TokenStoring) -> AccountAuthenticating
    let sessionFactory: (Account, TokenStoring, CalendarSelectionStoring) -> (auth: AccountAuthenticating, calendar: CalendarServicing)
}

final class AccountRegistry: AccountsManaging {
    private struct Live {
        let auth: AccountAuthenticating
        let calendar: CalendarServicing
    }

    private let accountStore: AccountStoring
    private let legacyMigration: LegacyAccountMigrating
    private let factories: AccountSessionFactories

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

    init(accountStore: AccountStoring, legacyMigration: LegacyAccountMigrating, factories: AccountSessionFactories) {
        self.accountStore = accountStore
        self.legacyMigration = legacyMigration
        self.factories = factories
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

    func addAccount(provider: AccountProvider) async throws -> Account {
        try await connectAndCommit(loginHint: nil)
    }

    func reconnect(accountId: String) async throws {
        let loginHint = accounts.first { $0.id == accountId }?.label
        _ = try await connectAndCommit(loginHint: loginHint)
    }

    func signOut(accountId: String) async {
        factories.scopedTokenStore(accountId).setRefreshToken(nil)
        factories.scopedCalendarSelectionStore(accountId).selectedCalendarIds = nil
        accounts.removeAll { $0.id == accountId }
        live.removeValue(forKey: accountId)
        statuses.removeValue(forKey: accountId)
        calendarsByAccount.removeValue(forKey: accountId)
        accountStore.accounts = accounts
    }

    func poll(fullResync: Bool) async -> (triggers: [Trigger], authoritativeAccountIds: Set<String>) {
        var triggers: [Trigger] = []
        var authoritativeAccountIds: Set<String> = []
        for account in accounts {
            guard let session = live[account.id] else { continue }
            do {
                triggers += try await session.calendar.poll(fullResync: fullResync)
                authoritativeAccountIds.insert(account.id)
                statuses[account.id] = .connected
                calendarsByAccount[account.id] = (try? await session.calendar.availableCalendars()) ?? calendarsByAccount[account.id] ?? []
            } catch AuthError.refreshTokenRevoked {
                print("[AccountRegistry] poll: \(account.id) needs reauth")
                statuses[account.id] = .needsReauth
            } catch {
                print("[AccountRegistry] poll failed for \(account.id): \(error)")
            }
        }
        return (triggers, authoritativeAccountIds)
    }

    private func connectAndCommit(loginHint: String?) async throws -> Account {
        let provisionalToken = InMemoryTokenStore()
        let provisionalAuth = factories.provisionalAuthFactory(provisionalToken)
        try await provisionalAuth.connect(loginHint: loginHint)
        let account = try await provisionalAuth.identity()

        factories.scopedTokenStore(account.id).setRefreshToken(provisionalToken.refreshToken())

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
        let (auth, calendar) = factories.sessionFactory(account, factories.scopedTokenStore(account.id), factories.scopedCalendarSelectionStore(account.id))
        return Live(auth: auth, calendar: calendar)
    }
}
