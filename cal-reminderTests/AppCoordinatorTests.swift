import XCTest
@testable import cal_reminder

/// A fully in-memory `AccountsManaging`, so `AppCoordinatorTests` exercises only
/// `AppCoordinator`'s own orchestration — the multi-Account internals (Keychain scoping,
/// per-session error isolation, the legacy migration) are `AccountRegistryTests`' job.
private final class FakeAccountsManaging: AccountsManaging {
    var sessions: [AccountSession] = []
    var pollTriggers: [Trigger] = []
    var pollAnyAccountSucceeded = true
    var addAccountResult: Account?
    var addAccountError: Error?
    var reconnectError: Error?

    private(set) var restoreCallCount = 0
    private(set) var verifySessionsCallCount = 0
    private(set) var pollCallCount = 0
    private(set) var receivedFullResyncFlags: [Bool] = []
    private(set) var signOutCalls: [String] = []
    private(set) var reconnectCalls: [String] = []
    private(set) var addAccountCallCount = 0

    func restore() async {
        restoreCallCount += 1
    }

    func verifySessions() async {
        verifySessionsCallCount += 1
    }

    func addAccount(provider: AccountProvider) async throws -> Account {
        addAccountCallCount += 1
        if let addAccountError { throw addAccountError }
        guard let account = addAccountResult else { throw AuthError.notConnected }
        sessions.append(AccountSession(account: account, connectionStatus: .connected))
        return account
    }

    func reconnect(accountId: String) async throws {
        reconnectCalls.append(accountId)
        if let reconnectError { throw reconnectError }
        if let index = sessions.firstIndex(where: { $0.id == accountId }) {
            sessions[index].connectionStatus = .connected
        }
    }

    func signOut(accountId: String) async {
        signOutCalls.append(accountId)
        sessions.removeAll { $0.id == accountId }
    }

    func poll(fullResync: Bool) async -> (triggers: [Trigger], anyAccountSucceeded: Bool) {
        pollCallCount += 1
        receivedFullResyncFlags.append(fullResync)
        return (pollTriggers, pollAnyAccountSucceeded)
    }
}

private final class FakeScheduler: Scheduling {
    private(set) var scheduledTriggers: [[Trigger]] = []
    private(set) var enabledCalls: [Bool] = []
    private(set) var cancelAllCallCount = 0
    private var armed: [String: Trigger] = [:]

    func schedule(_ triggers: [Trigger]) async {
        scheduledTriggers.append(triggers)
        for trigger in triggers {
            armed[trigger.id] = trigger
        }
    }

    func setEnabled(_ enabled: Bool) async {
        enabledCalls.append(enabled)
    }

    func cancelAll() async {
        cancelAllCallCount += 1
        armed.removeAll()
    }

    func nextArmedTrigger() async -> Trigger? {
        armed.values.min { $0.fireDate < $1.fireDate }
    }
}

private actor NoOpAnimator: OverlayAnimating {
    func animate(text: String, calendarColorHex: String?) async {}
}

@MainActor
final class AppCoordinatorTests: XCTestCase {
    private func trigger(id: String, minutesFromNow: TimeInterval) -> Trigger {
        let start = Date().addingTimeInterval(minutesFromNow * 60)
        return Trigger(id: id, eventTitle: "Standup", startDate: start, fireDate: start, minutesBefore: 0)
    }

    private func account(_ id: String = "google:a", label: String = "a@example.com") -> Account {
        Account(id: id, provider: .google, label: label)
    }

    private func makeCoordinator(
        accounts: FakeAccountsManaging = FakeAccountsManaging(),
        scheduler: FakeScheduler = FakeScheduler()
    ) -> AppCoordinator {
        AppCoordinator(
            accounts: accounts,
            scheduler: scheduler,
            overlay: OverlayPresenter(animator: NoOpAnimator())
        )
    }

    func test_startCallsRestoreThenVerifySessionsThenPoll() async throws {
        // Arrange
        let accounts = FakeAccountsManaging()
        let coordinator = makeCoordinator(accounts: accounts)

        // Act
        coordinator.start()
        try await Task.sleep(nanoseconds: 50_000_000)

        // Assert
        XCTAssertEqual(accounts.restoreCallCount, 1)
        XCTAssertEqual(accounts.verifySessionsCallCount, 1)
        XCTAssertEqual(accounts.pollCallCount, 1)
    }

    func test_startPopulatesStateFromRegistrySessions() async throws {
        // Arrange (RF-14: every connected Account is reflected in AppState)
        let accounts = FakeAccountsManaging()
        accounts.sessions = [
            AccountSession(account: account("google:a", label: "a@example.com"), connectionStatus: .connected),
            AccountSession(account: account("google:b", label: "b@example.com"), connectionStatus: .needsReauth)
        ]
        let coordinator = makeCoordinator(accounts: accounts)

        // Act
        coordinator.start()
        try await Task.sleep(nanoseconds: 50_000_000)

        // Assert
        XCTAssertEqual(coordinator.state.accounts.map(\.id).sorted(), ["google:a", "google:b"])
        XCTAssertEqual(coordinator.state.statusTitle, "2 accounts · 1 needs reconnecting")
    }

    func test_successfulPollUpdatesStateAndForwardsToScheduler() async {
        // Arrange
        let accounts = FakeAccountsManaging()
        let upcoming = trigger(id: "evt1#5", minutesFromNow: 5)
        accounts.pollTriggers = [upcoming]
        let scheduler = FakeScheduler()
        let coordinator = makeCoordinator(accounts: accounts, scheduler: scheduler)

        // Act
        await coordinator.poll()

        // Assert
        XCTAssertEqual(coordinator.state.nextTrigger?.id, "evt1#5")
        XCTAssertEqual(scheduler.scheduledTriggers.last?.map(\.id), ["evt1#5"])
    }

    func test_nextTriggerSurvivesAPollWithNoChanges() async {
        // Arrange: an incremental Poll (RNF-06) can return no changed Events even though
        // an earlier-armed Trigger is still upcoming — nextTrigger must not go stale to nil.
        let accounts = FakeAccountsManaging()
        let upcoming = trigger(id: "evt1#5", minutesFromNow: 5)
        accounts.pollTriggers = [upcoming]
        let coordinator = makeCoordinator(accounts: accounts)
        await coordinator.poll()
        XCTAssertEqual(coordinator.state.nextTrigger?.id, "evt1#5")

        // Act: next Poll's delta is empty (nothing changed on the Calendar)
        accounts.pollTriggers = []
        await coordinator.poll()

        // Assert
        XCTAssertEqual(coordinator.state.nextTrigger?.id, "evt1#5")
    }

    func test_toggleEnabledFlipsStateAndCallsScheduler() async throws {
        // Arrange
        let scheduler = FakeScheduler()
        let coordinator = makeCoordinator(scheduler: scheduler)
        XCTAssertTrue(coordinator.state.enabled)

        // Act
        coordinator.toggleEnabled()

        // Assert (state flips synchronously)
        XCTAssertFalse(coordinator.state.enabled)

        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(scheduler.enabledCalls, [false])
    }

    func test_addAccountCallsRegistryThenPolls() async throws {
        // Arrange (RF-14)
        let accounts = FakeAccountsManaging()
        accounts.addAccountResult = account("google:new", label: "new@example.com")
        let coordinator = makeCoordinator(accounts: accounts)

        // Act
        coordinator.addAccount()
        try await Task.sleep(nanoseconds: 50_000_000)

        // Assert
        XCTAssertEqual(accounts.addAccountCallCount, 1)
        XCTAssertEqual(accounts.pollCallCount, 1)
        XCTAssertEqual(coordinator.state.accounts.map(\.id), ["google:new"])
    }

    func test_reconnectCallsRegistryWithTheRightAccountThenPolls() async throws {
        // Arrange (RF-14)
        let accounts = FakeAccountsManaging()
        accounts.sessions = [AccountSession(account: account(), connectionStatus: .needsReauth)]
        let coordinator = makeCoordinator(accounts: accounts)

        // Act
        coordinator.reconnect(accountId: "google:a")
        try await Task.sleep(nanoseconds: 50_000_000)

        // Assert
        XCTAssertEqual(accounts.reconnectCalls, ["google:a"])
        XCTAssertEqual(accounts.pollCallCount, 1)
    }

    func test_wakeCancelsSchedulerBeforeRePolling() async {
        // Arrange
        let accounts = FakeAccountsManaging()
        let upcoming = trigger(id: "evt1#5", minutesFromNow: 5)
        accounts.pollTriggers = [upcoming]
        let scheduler = FakeScheduler()
        let coordinator = makeCoordinator(accounts: accounts, scheduler: scheduler)

        // Act
        await coordinator.handleWake()

        // Assert
        XCTAssertEqual(scheduler.cancelAllCallCount, 1)
        XCTAssertEqual(scheduler.scheduledTriggers.last?.map(\.id), ["evt1#5"])
    }

    func test_calendarsChangedCancelsSchedulerAndRePolls() async throws {
        // Arrange (RF-10: a selection change re-Polls immediately, mirroring handleWake)
        let accounts = FakeAccountsManaging()
        let upcoming = trigger(id: "evt1#5", minutesFromNow: 5)
        accounts.pollTriggers = [upcoming]
        let scheduler = FakeScheduler()
        let coordinator = makeCoordinator(accounts: accounts, scheduler: scheduler)

        // Act
        coordinator.calendarsChanged()
        try await Task.sleep(nanoseconds: 50_000_000)

        // Assert
        XCTAssertEqual(scheduler.cancelAllCallCount, 1)
        XCTAssertEqual(accounts.pollCallCount, 1)
        XCTAssertEqual(scheduler.scheduledTriggers.last?.map(\.id), ["evt1#5"])
    }

    func test_refreshNowTriggersPollAndTogglesRefreshingFlag() async throws {
        // Arrange (RF-12: manual Poll)
        let accounts = FakeAccountsManaging()
        let coordinator = makeCoordinator(accounts: accounts)

        // Act
        coordinator.refreshNow()

        // Assert: flips true synchronously, then clears once the Poll completes.
        XCTAssertTrue(coordinator.state.refreshing)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(coordinator.state.refreshing)
        XCTAssertEqual(accounts.pollCallCount, 1)
    }

    func test_refreshNowRequestsAFullResyncWhileOtherPollsStayIncremental() async throws {
        // Arrange (SPEC-013: only the manual refresh discards the syncTokens)
        let accounts = FakeAccountsManaging()
        let coordinator = makeCoordinator(accounts: accounts)

        // Act
        await coordinator.poll()
        await coordinator.handleWake()
        coordinator.refreshNow()
        try await Task.sleep(nanoseconds: 50_000_000)

        // Assert
        XCTAssertEqual(accounts.receivedFullResyncFlags, [false, false, true])
    }

    func test_refreshNowRebuildsTheArmedSetDroppingVanishedTriggers() async throws {
        // Arrange: a Trigger is armed, then its Event disappears from the Poll window
        // (deleted or rescheduled) — a full resync must not report it anymore.
        let accounts = FakeAccountsManaging()
        accounts.pollTriggers = [trigger(id: "evt1#5", minutesFromNow: 5)]
        let scheduler = FakeScheduler()
        let coordinator = makeCoordinator(accounts: accounts, scheduler: scheduler)
        await coordinator.poll()
        XCTAssertEqual(coordinator.state.nextTrigger?.id, "evt1#5")

        // Act
        accounts.pollTriggers = []
        coordinator.refreshNow()
        try await Task.sleep(nanoseconds: 50_000_000)

        // Assert
        XCTAssertEqual(scheduler.cancelAllCallCount, 1)
        XCTAssertNil(coordinator.state.nextTrigger)
    }

    func test_failedRefreshNowKeepsTheArmedTriggers() async throws {
        // Arrange (RNF-04: a total outage across every Account mid-refresh must not
        // disarm everything — mirrors the single-account build never reaching
        // `cancelAll()` when its one Poll call threw)
        let accounts = FakeAccountsManaging()
        accounts.pollTriggers = [trigger(id: "evt1#5", minutesFromNow: 5)]
        let scheduler = FakeScheduler()
        let coordinator = makeCoordinator(accounts: accounts, scheduler: scheduler)
        await coordinator.poll()

        // Act
        accounts.pollTriggers = []
        accounts.pollAnyAccountSucceeded = false
        coordinator.refreshNow()
        try await Task.sleep(nanoseconds: 50_000_000)

        // Assert
        XCTAssertEqual(scheduler.cancelAllCallCount, 0)
        XCTAssertEqual(coordinator.state.nextTrigger?.id, "evt1#5")
    }

    func test_signOutCancelsSchedulerAndDropsTheAccountFromState() async throws {
        // Arrange (RF-14 "Sign out" — per-Account, mirrors the old single-account logout)
        let accounts = FakeAccountsManaging()
        accounts.sessions = [AccountSession(account: account(), connectionStatus: .connected)]
        accounts.pollTriggers = [trigger(id: "evt1#5", minutesFromNow: 5)]
        let scheduler = FakeScheduler()
        let coordinator = makeCoordinator(accounts: accounts, scheduler: scheduler)
        await coordinator.poll()
        XCTAssertNotNil(coordinator.state.nextTrigger)

        // Act
        accounts.pollTriggers = []
        coordinator.signOut(accountId: "google:a")
        try await Task.sleep(nanoseconds: 50_000_000)

        // Assert
        XCTAssertEqual(accounts.signOutCalls, ["google:a"])
        XCTAssertEqual(scheduler.cancelAllCallCount, 1)
        XCTAssertNil(coordinator.state.nextTrigger)
        XCTAssertTrue(coordinator.state.accounts.isEmpty)
    }
}
