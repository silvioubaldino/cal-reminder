import XCTest
@testable import cal_reminder

private final class FakeAuthManaging: AuthManaging {
    var isConnected = false
    var connectError: Error?
    var email: String? = "user@example.com"
    private(set) var connectCallCount = 0

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
        guard let email else { throw AuthError.notConnected }
        return email
    }
}

private final class FakeCalendarServicing: CalendarServicing {
    var triggers: [Trigger] = []
    var calendars: [CalendarInfo] = []
    var error: Error?
    private(set) var pollCallCount = 0

    func poll() async throws -> [Trigger] {
        pollCallCount += 1
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

    func schedule(_ triggers: [Trigger]) async {
        scheduledTriggers.append(triggers)
    }

    func setEnabled(_ enabled: Bool) async {
        enabledCalls.append(enabled)
    }

    func cancelAll() async {
        cancelAllCallCount += 1
    }
}

private actor NoOpAnimator: OverlayAnimating {
    func animate(text: String) async {}
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

    func test_startReflectsAuthConnectionStatus() {
        // Arrange
        let auth = FakeAuthManaging()
        auth.isConnected = true
        let coordinator = makeCoordinator(auth: auth)

        // Act
        coordinator.start()

        // Assert
        XCTAssertTrue(coordinator.state.connected)
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
        XCTAssertTrue(coordinator.state.connected)
        XCTAssertEqual(coordinator.state.nextTrigger?.id, "evt1#5")
        XCTAssertEqual(scheduler.scheduledTriggers.last?.map(\.id), ["evt1#5"])
    }

    func test_failedPollKeepsConnectedAtAuthIsConnected() async {
        // Arrange
        let auth = FakeAuthManaging()
        auth.isConnected = true
        let calendar = FakeCalendarServicing()
        calendar.error = URLError(.notConnectedToInternet)
        let coordinator = makeCoordinator(auth: auth, calendar: calendar)

        // Act
        await coordinator.poll()

        // Assert
        XCTAssertTrue(coordinator.state.connected)
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

    func test_startFetchesConnectedUserEmail() async throws {
        // Arrange
        let auth = FakeAuthManaging()
        auth.isConnected = true
        auth.email = "user@example.com"
        let coordinator = makeCoordinator(auth: auth)

        // Act
        coordinator.start()
        try await Task.sleep(nanoseconds: 20_000_000)

        // Assert
        XCTAssertEqual(coordinator.state.userEmail, "user@example.com")
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
        XCTAssertTrue(coordinator.state.connected)
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
}
