import XCTest
@testable import cal_reminder

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
        let accounts = FakeAccountsManaging()
        let coordinator = makeCoordinator(accounts: accounts)

        coordinator.start()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(accounts.restoreCallCount, 1)
        XCTAssertEqual(accounts.verifySessionsCallCount, 1)
        XCTAssertEqual(accounts.pollCallCount, 1)
    }

    func test_startPopulatesStateFromRegistrySessions() async throws {
        let accounts = FakeAccountsManaging()
        accounts.sessions = [
            AccountSession(account: account("google:a", label: "a@example.com"), connectionStatus: .connected),
            AccountSession(account: account("google:b", label: "b@example.com"), connectionStatus: .needsReauth)
        ]
        let coordinator = makeCoordinator(accounts: accounts)

        coordinator.start()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(coordinator.state.accounts.map(\.id).sorted(), ["google:a", "google:b"])
        XCTAssertEqual(coordinator.state.statusTitle, "2 accounts · 1 needs reconnecting")
    }

    func test_successfulPollUpdatesStateAndForwardsToScheduler() async {
        let accounts = FakeAccountsManaging()
        let upcoming = trigger(id: "evt1#5", minutesFromNow: 5)
        accounts.pollTriggers = [upcoming]
        let scheduler = FakeScheduler()
        let coordinator = makeCoordinator(accounts: accounts, scheduler: scheduler)

        await coordinator.poll()

        XCTAssertEqual(coordinator.state.nextTrigger?.id, "evt1#5")
        XCTAssertEqual(scheduler.scheduledTriggers.last?.map(\.id), ["evt1#5"])
    }

    func test_nextTriggerSurvivesAPollWithNoChanges() async {
        let accounts = FakeAccountsManaging()
        let upcoming = trigger(id: "evt1#5", minutesFromNow: 5)
        accounts.pollTriggers = [upcoming]
        let coordinator = makeCoordinator(accounts: accounts)
        await coordinator.poll()
        XCTAssertEqual(coordinator.state.nextTrigger?.id, "evt1#5")

        accounts.pollTriggers = []
        await coordinator.poll()

        XCTAssertEqual(coordinator.state.nextTrigger?.id, "evt1#5")
    }

    func test_toggleEnabledFlipsStateAndCallsScheduler() async throws {
        let scheduler = FakeScheduler()
        let coordinator = makeCoordinator(scheduler: scheduler)
        XCTAssertTrue(coordinator.state.enabled)

        coordinator.toggleEnabled()

        XCTAssertFalse(coordinator.state.enabled)

        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(scheduler.enabledCalls, [false])
    }

    func test_addAccountCallsRegistryThenPolls() async throws {
        let accounts = FakeAccountsManaging()
        accounts.addAccountResult = account("google:new", label: "new@example.com")
        let coordinator = makeCoordinator(accounts: accounts)

        coordinator.addAccount()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(accounts.addAccountCallCount, 1)
        XCTAssertEqual(accounts.pollCallCount, 1)
        XCTAssertEqual(coordinator.state.accounts.map(\.id), ["google:new"])
    }

    func test_reconnectCallsRegistryWithTheRightAccountThenPolls() async throws {
        let accounts = FakeAccountsManaging()
        accounts.sessions = [AccountSession(account: account(), connectionStatus: .needsReauth)]
        let coordinator = makeCoordinator(accounts: accounts)

        coordinator.reconnect(accountId: "google:a")
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(accounts.reconnectCalls, ["google:a"])
        XCTAssertEqual(accounts.pollCallCount, 1)
    }

    func test_wakeCancelsSchedulerBeforeRePolling() async {
        let accounts = FakeAccountsManaging()
        let upcoming = trigger(id: "evt1#5", minutesFromNow: 5)
        accounts.pollTriggers = [upcoming]
        let scheduler = FakeScheduler()
        let coordinator = makeCoordinator(accounts: accounts, scheduler: scheduler)

        await coordinator.handleWake()

        XCTAssertEqual(scheduler.cancelAllCallCount, 1)
        XCTAssertEqual(scheduler.scheduledTriggers.last?.map(\.id), ["evt1#5"])
    }

    func test_calendarsChangedCancelsSchedulerAndRePolls() async throws {
        let accounts = FakeAccountsManaging()
        let upcoming = trigger(id: "evt1#5", minutesFromNow: 5)
        accounts.pollTriggers = [upcoming]
        let scheduler = FakeScheduler()
        let coordinator = makeCoordinator(accounts: accounts, scheduler: scheduler)

        coordinator.calendarsChanged()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertGreaterThanOrEqual(scheduler.cancelAllCallCount, 1)
        XCTAssertEqual(accounts.pollCallCount, 1)
        XCTAssertEqual(scheduler.scheduledTriggers.last?.map(\.id), ["evt1#5"])
        XCTAssertEqual(
            accounts.receivedFullResyncFlags,
            [true],
            "an incremental Poll would report no Events for the Calendars that kept their syncToken, losing their armed Triggers"
        )
    }

    func test_remindersChangedCancelsSchedulerAndRebuildsTriggersWithAFullResync() async throws {
        // Arrange — a Reminder-selection change (RF-15) must not wait for the next Poll, and
        // an incremental one would return no Events (AYD-008)
        let accounts = FakeAccountsManaging()
        let upcoming = trigger(id: "evt1#1", minutesFromNow: 5)
        accounts.pollTriggers = [upcoming]
        let scheduler = FakeScheduler()
        let coordinator = makeCoordinator(accounts: accounts, scheduler: scheduler)

        // Act
        coordinator.remindersChanged()
        try await Task.sleep(nanoseconds: 50_000_000)

        // Assert
        XCTAssertGreaterThanOrEqual(scheduler.cancelAllCallCount, 1)
        XCTAssertEqual(accounts.receivedFullResyncFlags, [true])
        XCTAssertEqual(scheduler.scheduledTriggers.last?.map(\.id), ["evt1#1"])
    }

    func test_refreshNowTriggersPollAndTogglesRefreshingFlag() async throws {
        let accounts = FakeAccountsManaging()
        let coordinator = makeCoordinator(accounts: accounts)

        coordinator.refreshNow()

        XCTAssertTrue(coordinator.state.refreshing)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(coordinator.state.refreshing)
        XCTAssertEqual(accounts.pollCallCount, 1)
    }

    func test_refreshNowRequestsAFullResyncWhileOtherPollsStayIncremental() async throws {
        let accounts = FakeAccountsManaging()
        let coordinator = makeCoordinator(accounts: accounts)

        await coordinator.poll()
        await coordinator.handleWake()
        coordinator.refreshNow()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(accounts.receivedFullResyncFlags, [false, false, true])
    }

    func test_refreshNowRebuildsTheArmedSetDroppingVanishedTriggers() async throws {
        let accounts = FakeAccountsManaging()
        accounts.pollTriggers = [trigger(id: "evt1#5", minutesFromNow: 5)]
        let scheduler = FakeScheduler()
        let coordinator = makeCoordinator(accounts: accounts, scheduler: scheduler)
        await coordinator.poll()
        XCTAssertEqual(coordinator.state.nextTrigger?.id, "evt1#5")

        accounts.pollTriggers = []
        coordinator.refreshNow()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(scheduler.cancelAllCallCount, 1)
        XCTAssertNil(coordinator.state.nextTrigger)
    }

    func test_failedRefreshNowKeepsTheArmedTriggers() async throws {
        let accounts = FakeAccountsManaging()
        accounts.pollTriggers = [trigger(id: "evt1#5", minutesFromNow: 5)]
        let scheduler = FakeScheduler()
        let coordinator = makeCoordinator(accounts: accounts, scheduler: scheduler)
        await coordinator.poll()

        accounts.pollTriggers = []
        accounts.pollAnyAccountSucceeded = false
        coordinator.refreshNow()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(scheduler.cancelAllCallCount, 0)
        XCTAssertEqual(coordinator.state.nextTrigger?.id, "evt1#5")
    }

    func test_signOutCancelsSchedulerAndDropsTheAccountFromState() async throws {
        let accounts = FakeAccountsManaging()
        accounts.sessions = [AccountSession(account: account(), connectionStatus: .connected)]
        accounts.pollTriggers = [trigger(id: "evt1#5", minutesFromNow: 5)]
        let scheduler = FakeScheduler()
        let coordinator = makeCoordinator(accounts: accounts, scheduler: scheduler)
        await coordinator.poll()
        XCTAssertNotNil(coordinator.state.nextTrigger)

        accounts.pollTriggers = []
        coordinator.signOut(accountId: "google:a")
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(accounts.signOutCalls, ["google:a"])
        XCTAssertEqual(scheduler.cancelAllCallCount, 1)
        XCTAssertNil(coordinator.state.nextTrigger)
        XCTAssertTrue(coordinator.state.accounts.isEmpty)
    }
}
