import XCTest
@testable import cal_reminder

private final class FakeAccountsManaging: AccountsManaging {
    var sessions: [AccountSession] = []
    var pollTriggers: [Trigger] = []
    /// Every Account this fake's next Poll succeeded for — defaults to none, so a test that
    /// never sets it can't accidentally claim authority to cancel something (AYD-011).
    var pollAuthoritativeAccountIds: Set<String> = []
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

    func poll(fullResync: Bool) async -> (triggers: [Trigger], authoritativeAccountIds: Set<String>) {
        pollCallCount += 1
        receivedFullResyncFlags.append(fullResync)
        return (pollTriggers, pollAuthoritativeAccountIds)
    }
}

private final class FakeScheduler: Scheduling {
    private(set) var reconcileCalls: [(triggers: [Trigger], accountIds: Set<String>)] = []
    private(set) var enabledCalls: [Bool] = []
    private(set) var cancelledAccountIds: [String] = []
    private(set) var rearmAllCallCount = 0
    private var armed: [String: Trigger] = [:]

    func reconcile(_ triggers: [Trigger], authoritativeFor accountIds: Set<String>) async {
        reconcileCalls.append((triggers, accountIds))
        for trigger in triggers {
            armed[trigger.id] = trigger
        }
        let incomingIds = Set(triggers.map(\.id))
        let vanishedIds = armed.values
            .filter { accountIds.contains($0.accountId) && !incomingIds.contains($0.id) }
            .map(\.id)
        for id in vanishedIds {
            armed.removeValue(forKey: id)
        }
    }

    func setEnabled(_ enabled: Bool) async {
        enabledCalls.append(enabled)
    }

    func cancel(accountId: String) async {
        cancelledAccountIds.append(accountId)
        let ids = armed.values.filter { $0.accountId == accountId }.map(\.id)
        for id in ids {
            armed.removeValue(forKey: id)
        }
    }

    func rearmAll() async {
        rearmAllCallCount += 1
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
    private func trigger(id: String, minutesFromNow: TimeInterval, accountId: String = "google:a") -> Trigger {
        let start = Date().addingTimeInterval(minutesFromNow * 60)
        return Trigger(id: id, eventTitle: "Standup", startDate: start, fireDate: start, minutesBefore: 0, accountId: accountId)
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
        XCTAssertEqual(scheduler.reconcileCalls.last?.triggers.map(\.id), ["evt1#5"])
    }

    func test_nextTriggerSurvivesAPollWithNoChanges() async {
        // A Poll that never claimed authority for "google:a" (the default here) can't cancel
        // anything from it — the same conservative default that keeps a failed refresh's
        // armed Triggers intact (`test_failedRefreshNowKeepsTheArmedTriggers`). A real,
        // *authoritative* empty result is exactly what CalendarService's replica (AYD-011)
        // now guarantees never happens for an Event that's still upcoming.
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

    func test_wakeReArmsPendingTriggersBeforeRePolling() async {
        // AYD-011: waking used to cancel every armed Trigger and hope the re-poll brought them
        // all back; it now re-arms what's already known and only reconciles from there.
        let accounts = FakeAccountsManaging()
        let upcoming = trigger(id: "evt1#5", minutesFromNow: 5)
        accounts.pollTriggers = [upcoming]
        let scheduler = FakeScheduler()
        let coordinator = makeCoordinator(accounts: accounts, scheduler: scheduler)

        await coordinator.handleWake()

        XCTAssertEqual(scheduler.rearmAllCallCount, 1)
        XCTAssertEqual(scheduler.reconcileCalls.last?.triggers.map(\.id), ["evt1#5"])
    }

    func test_calendarsChangedRebuildsTriggersWithAFullResync() async throws {
        let accounts = FakeAccountsManaging()
        let upcoming = trigger(id: "evt1#5", minutesFromNow: 5)
        accounts.pollTriggers = [upcoming]
        let scheduler = FakeScheduler()
        let coordinator = makeCoordinator(accounts: accounts, scheduler: scheduler)

        coordinator.calendarsChanged()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(accounts.pollCallCount, 1)
        XCTAssertEqual(scheduler.reconcileCalls.last?.triggers.map(\.id), ["evt1#5"])
        XCTAssertEqual(
            accounts.receivedFullResyncFlags,
            [true],
            "a newly selected Calendar has no syncToken yet, so only a full resync picks it up right away"
        )
    }

    func test_remindersChangedRebuildsTriggersWithAFullResync() async throws {
        // Arrange — a Reminder-selection change (RF-15) must not wait for the next Poll
        let accounts = FakeAccountsManaging()
        let upcoming = trigger(id: "evt1#1", minutesFromNow: 5)
        accounts.pollTriggers = [upcoming]
        let scheduler = FakeScheduler()
        let coordinator = makeCoordinator(accounts: accounts, scheduler: scheduler)

        // Act
        coordinator.remindersChanged()
        try await Task.sleep(nanoseconds: 50_000_000)

        // Assert
        XCTAssertEqual(accounts.receivedFullResyncFlags, [true])
        XCTAssertEqual(scheduler.reconcileCalls.last?.triggers.map(\.id), ["evt1#1"])
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
        accounts.pollAuthoritativeAccountIds = ["google:a"]
        let scheduler = FakeScheduler()
        let coordinator = makeCoordinator(accounts: accounts, scheduler: scheduler)
        await coordinator.poll()
        XCTAssertEqual(coordinator.state.nextTrigger?.id, "evt1#5")

        accounts.pollTriggers = []
        coordinator.refreshNow()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(scheduler.reconcileCalls.last?.accountIds, ["google:a"])
        XCTAssertNil(coordinator.state.nextTrigger)
    }

    func test_failedRefreshNowKeepsTheArmedTriggers() async throws {
        let accounts = FakeAccountsManaging()
        accounts.pollTriggers = [trigger(id: "evt1#5", minutesFromNow: 5)]
        accounts.pollAuthoritativeAccountIds = ["google:a"]
        let scheduler = FakeScheduler()
        let coordinator = makeCoordinator(accounts: accounts, scheduler: scheduler)
        await coordinator.poll()

        accounts.pollTriggers = []
        accounts.pollAuthoritativeAccountIds = [] // this round's refresh failed for google:a
        coordinator.refreshNow()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(scheduler.reconcileCalls.last?.accountIds, [])
        XCTAssertEqual(coordinator.state.nextTrigger?.id, "evt1#5")
    }

    func test_signOutCancelsOnlyThatAccountsTriggersAndDropsItFromState() async throws {
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
        XCTAssertEqual(scheduler.cancelledAccountIds, ["google:a"])
        XCTAssertNil(coordinator.state.nextTrigger)
        XCTAssertTrue(coordinator.state.accounts.isEmpty)
    }
}
