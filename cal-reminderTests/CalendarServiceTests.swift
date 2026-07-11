import XCTest
@testable import cal_reminder

private final class StubGoogleCalendarAPI: GoogleCalendarAPIProtocol {
    var events: [GoogleEvent] = []
    var nextSyncToken: String?
    var defaultReminders: [GoogleCalendarDefaultReminder] = []
    private(set) var receivedSyncTokens: [String?] = []

    func listEvents(timeMin: Date, timeMax: Date, syncToken: String?) async throws -> (events: [GoogleEvent], nextSyncToken: String?) {
        receivedSyncTokens.append(syncToken)
        return (events, nextSyncToken)
    }

    func calendarDefaultReminders() async throws -> [GoogleCalendarDefaultReminder] {
        defaultReminders
    }
}

final class CalendarServiceTests: XCTestCase {
    private let fixedNow = Date(timeIntervalSince1970: 1_800_000_000) // 2027-01-15T08:00:00Z

    private func timedEvent(
        id: String,
        title: String,
        startDate: Date,
        useDefault: Bool = true,
        overrides: [GoogleEvent.ReminderOverride]? = nil
    ) -> GoogleEvent {
        let formatter = ISO8601DateFormatter()
        return GoogleEvent(
            id: id,
            summary: title,
            start: .init(dateTime: formatter.string(from: startDate), date: nil),
            reminders: .init(useDefault: useDefault, overrides: overrides)
        )
    }

    private func allDayEvent(id: String) -> GoogleEvent {
        GoogleEvent(
            id: id,
            summary: "Holiday",
            start: .init(dateTime: nil, date: "2027-01-16"),
            reminders: nil
        )
    }

    func test_onlyTimedEventsProduceTriggers() async throws {
        // Arrange
        let api = StubGoogleCalendarAPI()
        api.events = [
            timedEvent(id: "evt-timed", title: "Standup", startDate: fixedNow.addingTimeInterval(600)),
            allDayEvent(id: "evt-allday")
        ]
        api.defaultReminders = [GoogleCalendarDefaultReminder(method: "popup", minutes: 10)]
        let service = CalendarService(api: api, clock: { self.fixedNow })

        // Act
        let triggers = try await service.poll()

        // Assert
        XCTAssertEqual(triggers.count, 1)
        XCTAssertEqual(triggers.first?.id, "evt-timed#10")
    }

    func test_resolvesRemindersPerRN04() async throws {
        // Arrange
        let api = StubGoogleCalendarAPI()
        let start = fixedNow.addingTimeInterval(3600)
        api.events = [
            timedEvent(id: "evt-default", title: "Uses default", startDate: start, useDefault: true),
            timedEvent(
                id: "evt-override",
                title: "Uses override",
                startDate: start,
                useDefault: false,
                overrides: [.init(method: "popup", minutes: 5), .init(method: "email", minutes: 60)]
            )
        ]
        api.defaultReminders = [GoogleCalendarDefaultReminder(method: "popup", minutes: 15)]
        let service = CalendarService(api: api, clock: { self.fixedNow })

        // Act
        let triggers = try await service.poll()

        // Assert
        XCTAssertTrue(triggers.contains { $0.id == "evt-default#15" })
        XCTAssertTrue(triggers.contains { $0.id == "evt-override#5" })
        XCTAssertFalse(triggers.contains { $0.id == "evt-override#60" })
    }

    func test_oneTriggerPerPopupReminderWithCorrectFireDate() async throws {
        // Arrange
        let api = StubGoogleCalendarAPI()
        let start = fixedNow.addingTimeInterval(3600)
        api.events = [
            timedEvent(
                id: "evt1",
                title: "Standup",
                startDate: start,
                useDefault: false,
                overrides: [.init(method: "popup", minutes: 10), .init(method: "popup", minutes: 2)]
            )
        ]
        let service = CalendarService(api: api, clock: { self.fixedNow })

        // Act
        let triggers = try await service.poll()

        // Assert
        XCTAssertEqual(triggers.count, 2)
        let byMinutes = Dictionary(uniqueKeysWithValues: triggers.map { ($0.minutesBefore, $0) })
        XCTAssertEqual(byMinutes[10]?.id, "evt1#10")
        XCTAssertEqual(byMinutes[10]?.fireDate, start.addingTimeInterval(-10 * 60))
        XCTAssertEqual(byMinutes[2]?.id, "evt1#2")
        XCTAssertEqual(byMinutes[2]?.fireDate, start.addingTimeInterval(-2 * 60))
    }

    func test_usesSyncTokenOnSubsequentPolls() async throws {
        // Arrange
        let api = StubGoogleCalendarAPI()
        api.nextSyncToken = "token-abc"
        let service = CalendarService(api: api, clock: { self.fixedNow })

        // Act
        _ = try await service.poll()
        _ = try await service.poll()

        // Assert
        XCTAssertEqual(api.receivedSyncTokens, [nil, "token-abc"])
    }

    func test_cachesCalendarDefaultRemindersAcrossPolls() async throws {
        // Arrange
        let api = StubGoogleCalendarAPI()
        api.defaultReminders = [GoogleCalendarDefaultReminder(method: "popup", minutes: 10)]
        let service = CalendarService(api: api, clock: { self.fixedNow })

        // Act
        _ = try await service.poll()
        api.defaultReminders = [] // if the service re-fetched, this would change resolution
        api.events = [timedEvent(id: "evt1", title: "Standup", startDate: fixedNow.addingTimeInterval(600))]
        let triggers = try await service.poll()

        // Assert
        XCTAssertEqual(triggers.first?.id, "evt1#10")
    }
}
