import XCTest
@testable import cal_reminder

private final class FakeAuthManaging: AuthManaging {
    var isConnected = false
    var connectError: Error?
    var email: String? = "user@example.com"
    var userEmailError: Error?
    private(set) var connectCallCount = 0
    private(set) var disconnectCallCount = 0

    func connect() async throws {
        connectCallCount += 1
        if let connectError { throw connectError }
        isConnected = true
    }

    func accessToken() async throws -> String { "token" }

    func authorizedRequest(_ makeRequest: (_ accessToken: String) -> URLRequest) async throws -> (Data, HTTPURLResponse) {
        fatalError("not exercised by AppCoordinatorTests")
    }

    func userEmail() async throws -> String {
        if let userEmailError { throw userEmailError }
        guard let email else { throw AuthError.notConnected }
        return email
    }

    func disconnect() async {
        disconnectCallCount += 1
        isConnected = false
    }
}

private final class FakeCalendarServicing: CalendarServicing {
    var triggers: [Trigger] = []
    var calendars: [CalendarInfo] = []
    var error: Error?
    private(set) var pollCallCount = 0
    /// The `fullResync` flag received per call, in order (SPEC-013).
    private(set) var receivedFullResyncFlags: [Bool] = []

    func poll(fullResync: Bool) async throws -> [Trigger] {
        pollCallCount += 1
        receivedFullResyncFlags.append(fullResync)
        if let error { throw error }
        return triggers
    }

    func availableCalendars() async throws -> [CalendarInfo] {
        calendars
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

    private func makeCoordinator(
        auth: FakeAuthManaging = FakeAuthManaging(),
        calendar: FakeCalendarServicing = FakeCalendarServicing(),
        scheduler: FakeScheduler = FakeScheduler()
    ) -> AppCoordinator {
        AppCoordinator(
            auth: auth,
            calendar: calendar,
            scheduler: scheduler,
            overlay: OverlayPresenter(animator: NoOpAnimator())
        )
    }

    func test_startWithStoredTokenBeginsConnecting() {
        // Arrange
        let auth = FakeAuthManaging()
        auth.isConnected = true
        let coordinator = makeCoordinator(auth: auth)

        // Act
        coordinator.start()

        // Assert: synchronous transition, before the async verification call completes.
        XCTAssertEqual(coordinator.state.connectionStatus, .connecting)
    }

    func test_startWithNoStoredTokenIsDisconnected() {
        // Arrange
        let coordinator = makeCoordinator()

        // Act
        coordinator.start()

        // Assert
        XCTAssertEqual(coordinator.state.connectionStatus, .disconnected)
    }

    func test_startWithValidSessionVerifiesAndFetchesEmail() async throws {
        // Arrange
        let auth = FakeAuthManaging()
        auth.isConnected = true
        auth.email = "user@example.com"
        let coordinator = makeCoordinator(auth: auth)

        // Act
        coordinator.start()
        try await Task.sleep(nanoseconds: 50_000_000)

        // Assert
        XCTAssertEqual(coordinator.state.connectionStatus, .connected(email: "user@example.com"))
    }

    func test_startWithRevokedTokenBecomesNeedsReauth() async throws {
        // Arrange: a truly revoked token fails every authenticated call it touches — both
        // the startup verification and the concurrent background Poll.
        let auth = FakeAuthManaging()
        auth.isConnected = true
        auth.userEmailError = AuthError.refreshTokenRevoked
        let calendar = FakeCalendarServicing()
        calendar.error = AuthError.refreshTokenRevoked
        let coordinator = makeCoordinator(auth: auth, calendar: calendar)

        // Act
        coordinator.start()
        try await Task.sleep(nanoseconds: 50_000_000)

        // Assert
        XCTAssertEqual(coordinator.state.connectionStatus, .needsReauth)
    }

    func test_successfulPollUpdatesStateAndForwardsToScheduler() async {
        // Arrange
        let calendar = FakeCalendarServicing()
        let upcoming = trigger(id: "evt1#5", minutesFromNow: 5)
        calendar.triggers = [upcoming]
        let scheduler = FakeScheduler()
        let coordinator = makeCoordinator(calendar: calendar, scheduler: scheduler)

        // Act
        await coordinator.poll()

        // Assert
        XCTAssertEqual(coordinator.state.connectionStatus, .connected(email: "user@example.com"))
        XCTAssertEqual(coordinator.state.nextTrigger?.id, "evt1#5")
        XCTAssertEqual(scheduler.scheduledTriggers.last?.map(\.id), ["evt1#5"])
    }

    func test_nextTriggerSurvivesAPollWithNoChanges() async {
        // Arrange: an incremental Poll (RNF-06) can return no changed Events even though
        // an earlier-armed Trigger is still upcoming — nextTrigger must not go stale to nil.
        let calendar = FakeCalendarServicing()
        let upcoming = trigger(id: "evt1#5", minutesFromNow: 5)
        calendar.triggers = [upcoming]
        let coordinator = makeCoordinator(calendar: calendar)
        await coordinator.poll()
        XCTAssertEqual(coordinator.state.nextTrigger?.id, "evt1#5")

        // Act: next Poll's delta is empty (nothing changed on the Calendar)
        calendar.triggers = []
        await coordinator.poll()

        // Assert
        XCTAssertEqual(coordinator.state.nextTrigger?.id, "evt1#5")
    }

    func test_pollNetworkFailureKeepsSessionConnected() async {
        // Arrange: a successful Poll first establishes a connected session.
        let calendar = FakeCalendarServicing()
        let coordinator = makeCoordinator(calendar: calendar)
        await coordinator.poll()
        XCTAssertEqual(coordinator.state.connectionStatus, .connected(email: "user@example.com"))

        // Act: a transient network failure must not drop the session (RNF-04).
        calendar.error = URLError(.notConnectedToInternet)
        await coordinator.poll()

        // Assert
        XCTAssertEqual(coordinator.state.connectionStatus, .connected(email: "user@example.com"))
    }

    func test_pollAuthRevokedDropsToNeedsReauth() async {
        // Arrange: a successful Poll first establishes a connected session.
        let calendar = FakeCalendarServicing()
        let coordinator = makeCoordinator(calendar: calendar)
        await coordinator.poll()
        XCTAssertEqual(coordinator.state.connectionStatus, .connected(email: "user@example.com"))

        // Act
        calendar.error = AuthError.refreshTokenRevoked
        await coordinator.poll()

        // Assert
        XCTAssertEqual(coordinator.state.connectionStatus, .needsReauth)
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

    func test_reconnectCallsAuthConnectThenPolls() async throws {
        // Arrange
        let auth = FakeAuthManaging()
        let calendar = FakeCalendarServicing()
        let coordinator = makeCoordinator(auth: auth, calendar: calendar)

        // Act
        coordinator.reconnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        // Assert
        XCTAssertEqual(auth.connectCallCount, 1)
        XCTAssertEqual(calendar.pollCallCount, 1)
        XCTAssertEqual(coordinator.state.connectionStatus, .connected(email: "user@example.com"))
    }

    func test_wakeCancelsSchedulerBeforeRePolling() async {
        // Arrange
        let calendar = FakeCalendarServicing()
        let upcoming = trigger(id: "evt1#5", minutesFromNow: 5)
        calendar.triggers = [upcoming]
        let scheduler = FakeScheduler()
        let coordinator = makeCoordinator(calendar: calendar, scheduler: scheduler)

        // Act
        await coordinator.handleWake()

        // Assert
        XCTAssertEqual(scheduler.cancelAllCallCount, 1)
        XCTAssertEqual(scheduler.scheduledTriggers.last?.map(\.id), ["evt1#5"])
    }

    func test_pollPopulatesStateCalendars() async {
        // Arrange (RF-10: the menu reflects the account's Calendars after every Poll)
        let calendar = FakeCalendarServicing()
        calendar.calendars = [CalendarInfo(id: "A", title: "A", isPrimary: true)]
        let coordinator = makeCoordinator(calendar: calendar)

        // Act
        await coordinator.poll()

        // Assert
        XCTAssertEqual(coordinator.state.calendars, [CalendarInfo(id: "A", title: "A", isPrimary: true)])
    }

    func test_calendarsChangedCancelsSchedulerAndRePolls() async throws {
        // Arrange (RF-10: a selection change re-Polls immediately, mirroring handleWake)
        let calendar = FakeCalendarServicing()
        let upcoming = trigger(id: "evt1#5", minutesFromNow: 5)
        calendar.triggers = [upcoming]
        let scheduler = FakeScheduler()
        let coordinator = makeCoordinator(calendar: calendar, scheduler: scheduler)

        // Act
        coordinator.calendarsChanged()
        try await Task.sleep(nanoseconds: 50_000_000)

        // Assert
        XCTAssertEqual(scheduler.cancelAllCallCount, 1)
        XCTAssertEqual(calendar.pollCallCount, 1)
        XCTAssertEqual(scheduler.scheduledTriggers.last?.map(\.id), ["evt1#5"])
    }

    func test_refreshNowTriggersPollAndTogglesRefreshingFlag() async throws {
        // Arrange (RF-12: manual Poll)
        let calendar = FakeCalendarServicing()
        let coordinator = makeCoordinator(calendar: calendar)

        // Act
        coordinator.refreshNow()

        // Assert: flips true synchronously, then clears once the Poll completes.
        XCTAssertTrue(coordinator.state.refreshing)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(coordinator.state.refreshing)
        XCTAssertEqual(calendar.pollCallCount, 1)
    }

    func test_refreshNowRequestsAFullResyncWhileOtherPollsStayIncremental() async throws {
        // Arrange (SPEC-013: only the manual refresh discards the syncTokens)
        let calendar = FakeCalendarServicing()
        let coordinator = makeCoordinator(calendar: calendar)

        // Act
        await coordinator.poll()
        await coordinator.handleWake()
        coordinator.refreshNow()
        try await Task.sleep(nanoseconds: 50_000_000)

        // Assert
        XCTAssertEqual(calendar.receivedFullResyncFlags, [false, false, true])
    }

    func test_refreshNowRebuildsTheArmedSetDroppingVanishedTriggers() async throws {
        // Arrange: a Trigger is armed, then its Event disappears from the Poll window
        // (deleted or rescheduled) — a full resync must not report it anymore.
        let calendar = FakeCalendarServicing()
        calendar.triggers = [trigger(id: "evt1#5", minutesFromNow: 5)]
        let scheduler = FakeScheduler()
        let coordinator = makeCoordinator(calendar: calendar, scheduler: scheduler)
        await coordinator.poll()
        XCTAssertEqual(coordinator.state.nextTrigger?.id, "evt1#5")

        // Act
        calendar.triggers = []
        coordinator.refreshNow()
        try await Task.sleep(nanoseconds: 50_000_000)

        // Assert
        XCTAssertEqual(scheduler.cancelAllCallCount, 1)
        XCTAssertNil(coordinator.state.nextTrigger)
    }

    func test_failedRefreshNowKeepsTheArmedTriggers() async throws {
        // Arrange (RNF-04: a network failure mid-refresh must not disarm everything)
        let calendar = FakeCalendarServicing()
        calendar.triggers = [trigger(id: "evt1#5", minutesFromNow: 5)]
        let scheduler = FakeScheduler()
        let coordinator = makeCoordinator(calendar: calendar, scheduler: scheduler)
        await coordinator.poll()

        // Act
        calendar.error = URLError(.notConnectedToInternet)
        coordinator.refreshNow()
        try await Task.sleep(nanoseconds: 50_000_000)

        // Assert
        XCTAssertEqual(scheduler.cancelAllCallCount, 0)
        XCTAssertEqual(coordinator.state.nextTrigger?.id, "evt1#5")
        XCTAssertEqual(coordinator.state.connectionStatus, .connected(email: "user@example.com"))
    }

    func test_logoutCancelsTriggersDisconnectsAndClearsSession() async throws {
        // Arrange
        let calendar = FakeCalendarServicing()
        calendar.triggers = [trigger(id: "evt1#5", minutesFromNow: 5)]
        let scheduler = FakeScheduler()
        let auth = FakeAuthManaging()
        let coordinator = makeCoordinator(auth: auth, calendar: calendar, scheduler: scheduler)
        await coordinator.poll()
        XCTAssertNotNil(coordinator.state.nextTrigger)

        // Act
        coordinator.logout()
        try await Task.sleep(nanoseconds: 50_000_000)

        // Assert
        XCTAssertEqual(scheduler.cancelAllCallCount, 1)
        XCTAssertEqual(auth.disconnectCallCount, 1)
        XCTAssertEqual(coordinator.state.connectionStatus, .disconnected)
        XCTAssertNil(coordinator.state.nextTrigger)
    }
}
