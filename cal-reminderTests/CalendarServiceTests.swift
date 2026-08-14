import XCTest
@testable import cal_reminder

private final class StubGoogleCalendarAPI: GoogleCalendarAPIProtocol {
    var calendars: [GoogleCalendarListEntry] = [
        GoogleCalendarListEntry(id: "primary", summary: "Primary", primary: true, accessRole: "owner", backgroundColor: nil)
    ]
    /// Per-calendarId fixtures, keyed the same way the real API is keyed by `calendarId`.
    var events: [String: [GoogleEvent]] = [:]
    var nextSyncTokens: [String: String] = [:]
    var defaultReminders: [String: [GoogleCalendarDefaultReminder]?] = [:]
    /// Calendar ids that should fail once with a 410 (expired syncToken) before succeeding.
    var expireTokenOnce: Set<String> = []
    /// Calendar ids that always fail (e.g. access revoked mid-flight) — simulates a
    /// persistently broken Calendar that must not take down the whole Poll.
    var alwaysFail: Set<String> = []
    /// Calendar ids whose call fails because the session's refresh token is dead — unlike
    /// `alwaysFail`, this must propagate out of `poll()` instead of being skipped, since
    /// it's the whole session that's broken, not just this one Calendar (SPEC-010).
    var authRevokedFor: Set<String> = []

    private(set) var receivedCalendarIds: [String] = []
    private(set) var receivedSyncTokens: [String?] = []

    func listCalendars() async throws -> [GoogleCalendarListEntry] {
        calendars
    }

    func listEvents(calendarId: String, timeMin: Date, timeMax: Date, syncToken: String?) async throws -> (events: [GoogleEvent], nextSyncToken: String?, defaultReminders: [GoogleCalendarDefaultReminder]?) {
        receivedCalendarIds.append(calendarId)
        receivedSyncTokens.append(syncToken)
        if authRevokedFor.contains(calendarId) {
            throw AuthError.refreshTokenRevoked
        }
        if alwaysFail.contains(calendarId) {
            throw GoogleCalendarAPIError.unexpectedStatus(403)
        }
        if expireTokenOnce.contains(calendarId) {
            expireTokenOnce.remove(calendarId)
            throw GoogleCalendarAPIError.unexpectedStatus(410)
        }
        return (events[calendarId] ?? [], nextSyncTokens[calendarId], defaultReminders[calendarId] ?? [])
    }
}

private final class StubCalendarSelectionStore: CalendarSelectionStoring {
    var selectedCalendarIds: Set<String>?
    init(selectedCalendarIds: Set<String>? = nil) {
        self.selectedCalendarIds = selectedCalendarIds
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
        api.events["primary"] = [
            timedEvent(id: "evt-timed", title: "Standup", startDate: fixedNow.addingTimeInterval(600)),
            allDayEvent(id: "evt-allday")
        ]
        api.defaultReminders["primary"] = [GoogleCalendarDefaultReminder(method: "popup", minutes: 10)]
        let service = CalendarService(api: api, selectionStore: StubCalendarSelectionStore(), clock: { self.fixedNow })

        // Act
        let triggers = try await service.poll()

        // Assert
        XCTAssertEqual(triggers.count, 1)
        XCTAssertEqual(triggers.first?.id, "primary#evt-timed#10")
    }

    func test_resolvesRemindersPerRN04() async throws {
        // Arrange
        let api = StubGoogleCalendarAPI()
        let start = fixedNow.addingTimeInterval(3600)
        api.events["primary"] = [
            timedEvent(id: "evt-default", title: "Uses default", startDate: start, useDefault: true),
            timedEvent(
                id: "evt-override",
                title: "Uses override",
                startDate: start,
                useDefault: false,
                overrides: [.init(method: "popup", minutes: 5), .init(method: "email", minutes: 60)]
            )
        ]
        api.defaultReminders["primary"] = [GoogleCalendarDefaultReminder(method: "popup", minutes: 15)]
        let service = CalendarService(api: api, selectionStore: StubCalendarSelectionStore(), clock: { self.fixedNow })

        // Act
        let triggers = try await service.poll()

        // Assert
        XCTAssertTrue(triggers.contains { $0.id == "primary#evt-default#15" })
        XCTAssertTrue(triggers.contains { $0.id == "primary#evt-override#5" })
        XCTAssertFalse(triggers.contains { $0.id == "primary#evt-override#60" })
    }

    func test_oneTriggerPerPopupReminderWithCorrectFireDate() async throws {
        // Arrange
        let api = StubGoogleCalendarAPI()
        let start = fixedNow.addingTimeInterval(3600)
        api.events["primary"] = [
            timedEvent(
                id: "evt1",
                title: "Standup",
                startDate: start,
                useDefault: false,
                overrides: [.init(method: "popup", minutes: 10), .init(method: "popup", minutes: 2)]
            )
        ]
        let service = CalendarService(api: api, selectionStore: StubCalendarSelectionStore(), clock: { self.fixedNow })

        // Act
        let triggers = try await service.poll()

        // Assert
        XCTAssertEqual(triggers.count, 2)
        let byMinutes = Dictionary(uniqueKeysWithValues: triggers.map { ($0.minutesBefore, $0) })
        XCTAssertEqual(byMinutes[10]?.id, "primary#evt1#10")
        XCTAssertEqual(byMinutes[10]?.fireDate, start.addingTimeInterval(-10 * 60))
        XCTAssertEqual(byMinutes[2]?.id, "primary#evt1#2")
        XCTAssertEqual(byMinutes[2]?.fireDate, start.addingTimeInterval(-2 * 60))
    }

    func test_usesSyncTokenOnSubsequentPolls() async throws {
        // Arrange
        let api = StubGoogleCalendarAPI()
        api.nextSyncTokens["primary"] = "token-abc"
        let service = CalendarService(api: api, selectionStore: StubCalendarSelectionStore(), clock: { self.fixedNow })

        // Act
        _ = try await service.poll()
        _ = try await service.poll()

        // Assert
        XCTAssertEqual(api.receivedSyncTokens, [nil, "token-abc"])
    }

    func test_fullResyncPollDropsTheStoredSyncToken() async throws {
        // Arrange (SPEC-013: the manual refresh refetches the whole window)
        let api = StubGoogleCalendarAPI()
        api.nextSyncTokens["primary"] = "token-abc"
        let service = CalendarService(api: api, selectionStore: StubCalendarSelectionStore(), clock: { self.fixedNow })

        // Act
        _ = try await service.poll()
        _ = try await service.poll(fullResync: true)
        _ = try await service.poll()

        // Assert: full call, then a full call again despite the stored token, then
        // incremental from the token that full call returned.
        XCTAssertEqual(api.receivedSyncTokens, [nil, nil, "token-abc"])
    }

    func test_fullResyncKeepsTheCachedDefaultReminders() async throws {
        // Arrange: the cached defaults aren't sync state — dropping them would break
        // resolution (RN-04) if a later response omits them.
        let api = StubGoogleCalendarAPI()
        api.defaultReminders["primary"] = [GoogleCalendarDefaultReminder(method: "popup", minutes: 10)]
        let service = CalendarService(api: api, selectionStore: StubCalendarSelectionStore(), clock: { self.fixedNow })
        _ = try await service.poll()

        // Act
        api.defaultReminders.updateValue(nil, forKey: "primary")
        api.events["primary"] = [timedEvent(id: "evt1", title: "Standup", startDate: fixedNow.addingTimeInterval(600))]
        let triggers = try await service.poll(fullResync: true)

        // Assert
        XCTAssertEqual(triggers.first?.id, "primary#evt1#10")
    }

    func test_remembersDefaultRemindersWhenResponseOmitsThem() async throws {
        // Arrange
        let api = StubGoogleCalendarAPI()
        api.defaultReminders["primary"] = [GoogleCalendarDefaultReminder(method: "popup", minutes: 10)]
        let service = CalendarService(api: api, selectionStore: StubCalendarSelectionStore(), clock: { self.fixedNow })

        // Act
        _ = try await service.poll()
        // Store an explicit nil (not remove the key) to simulate a response that omits
        // defaults — `dict[key] = nil` would instead delete the entry.
        api.defaultReminders.updateValue(nil, forKey: "primary") // a response without defaults must not drop the last known
        api.events["primary"] = [timedEvent(id: "evt1", title: "Standup", startDate: fixedNow.addingTimeInterval(600))]
        let triggers = try await service.poll()

        // Assert
        XCTAssertEqual(triggers.first?.id, "primary#evt1#10")
    }

    func test_stampsEachCalendarsColorOnItsTriggers() async throws {
        // Arrange (RF-13: the Calendar Color travels on the Trigger to fire time)
        let api = StubGoogleCalendarAPI()
        api.calendars = [
            GoogleCalendarListEntry(id: "A", summary: "A", primary: true, accessRole: "owner", backgroundColor: "#0b8043"),
            GoogleCalendarListEntry(id: "B", summary: "B", primary: false, accessRole: "reader", backgroundColor: nil)
        ]
        api.events["A"] = [timedEvent(id: "evt-a", title: "A event", startDate: fixedNow.addingTimeInterval(600))]
        api.events["B"] = [timedEvent(id: "evt-b", title: "B event", startDate: fixedNow.addingTimeInterval(600))]
        api.defaultReminders["A"] = [GoogleCalendarDefaultReminder(method: "popup", minutes: 10)]
        api.defaultReminders["B"] = [GoogleCalendarDefaultReminder(method: "popup", minutes: 10)]
        let service = CalendarService(api: api, selectionStore: StubCalendarSelectionStore(), clock: { self.fixedNow })

        // Act
        let triggers = try await service.poll()

        // Assert
        let triggerA = try XCTUnwrap(triggers.first(where: { $0.id == "A#evt-a#10" }))
        let triggerB = try XCTUnwrap(triggers.first(where: { $0.id == "B#evt-b#10" }))
        XCTAssertEqual(triggerA.calendarColorHex, "#0b8043")
        XCTAssertNil(triggerB.calendarColorHex)
    }

    func test_defaultSelectionPollsEveryCalendar() async throws {
        // Arrange (RF-10: never-chosen selection = all Calendars)
        let api = StubGoogleCalendarAPI()
        api.calendars = [
            GoogleCalendarListEntry(id: "A", summary: "A", primary: true, accessRole: "owner", backgroundColor: nil),
            GoogleCalendarListEntry(id: "B", summary: "B", primary: false, accessRole: "reader", backgroundColor: nil)
        ]
        api.events["A"] = [timedEvent(id: "evt-a", title: "A event", startDate: fixedNow.addingTimeInterval(600))]
        api.events["B"] = [timedEvent(id: "evt-b", title: "B event", startDate: fixedNow.addingTimeInterval(600))]
        api.defaultReminders["A"] = [GoogleCalendarDefaultReminder(method: "popup", minutes: 10)]
        api.defaultReminders["B"] = [GoogleCalendarDefaultReminder(method: "popup", minutes: 10)]
        let service = CalendarService(api: api, selectionStore: StubCalendarSelectionStore(selectedCalendarIds: nil), clock: { self.fixedNow })

        // Act
        let triggers = try await service.poll()

        // Assert
        XCTAssertEqual(Set(api.receivedCalendarIds), ["A", "B"])
        XCTAssertEqual(Set(triggers.map(\.id)), ["A#evt-a#10", "B#evt-b#10"])
    }

    func test_onlySelectedCalendarsArePolled() async throws {
        // Arrange
        let api = StubGoogleCalendarAPI()
        api.calendars = [
            GoogleCalendarListEntry(id: "A", summary: "A", primary: true, accessRole: "owner", backgroundColor: nil),
            GoogleCalendarListEntry(id: "B", summary: "B", primary: false, accessRole: "reader", backgroundColor: nil)
        ]
        api.events["A"] = [timedEvent(id: "evt-a", title: "A event", startDate: fixedNow.addingTimeInterval(600))]
        api.events["B"] = [timedEvent(id: "evt-b", title: "B event", startDate: fixedNow.addingTimeInterval(600))]
        api.defaultReminders["A"] = [GoogleCalendarDefaultReminder(method: "popup", minutes: 10)]
        api.defaultReminders["B"] = [GoogleCalendarDefaultReminder(method: "popup", minutes: 10)]
        let service = CalendarService(api: api, selectionStore: StubCalendarSelectionStore(selectedCalendarIds: ["A"]), clock: { self.fixedNow })

        // Act
        let triggers = try await service.poll()

        // Assert
        XCTAssertEqual(api.receivedCalendarIds, ["A"])
        XCTAssertEqual(triggers.map(\.id), ["A#evt-a#10"])
    }

    func test_dedupeIdsArePrefixedWithCalendarId() async throws {
        // Arrange (same eventId in two Calendars must not collide, RN-03)
        let api = StubGoogleCalendarAPI()
        api.calendars = [
            GoogleCalendarListEntry(id: "A", summary: "A", primary: true, accessRole: "owner", backgroundColor: nil),
            GoogleCalendarListEntry(id: "B", summary: "B", primary: false, accessRole: "reader", backgroundColor: nil)
        ]
        let sharedEventId = "shared-evt"
        api.events["A"] = [timedEvent(id: sharedEventId, title: "Shared", startDate: fixedNow.addingTimeInterval(600))]
        api.events["B"] = [timedEvent(id: sharedEventId, title: "Shared", startDate: fixedNow.addingTimeInterval(600))]
        api.defaultReminders["A"] = [GoogleCalendarDefaultReminder(method: "popup", minutes: 10)]
        api.defaultReminders["B"] = [GoogleCalendarDefaultReminder(method: "popup", minutes: 10)]
        let service = CalendarService(api: api, selectionStore: StubCalendarSelectionStore(), clock: { self.fixedNow })

        // Act
        let triggers = try await service.poll()

        // Assert
        XCTAssertEqual(triggers.count, 2)
        XCTAssertEqual(Set(triggers.map(\.id)), ["A#\(sharedEventId)#10", "B#\(sharedEventId)#10"])
    }

    func test_perCalendarSyncTokenIsolation() async throws {
        // Arrange
        let api = StubGoogleCalendarAPI()
        api.calendars = [
            GoogleCalendarListEntry(id: "A", summary: "A", primary: true, accessRole: "owner", backgroundColor: nil),
            GoogleCalendarListEntry(id: "B", summary: "B", primary: false, accessRole: "reader", backgroundColor: nil)
        ]
        api.nextSyncTokens["A"] = "token-a"
        let service = CalendarService(api: api, selectionStore: StubCalendarSelectionStore(), clock: { self.fixedNow })

        // Act
        _ = try await service.poll()
        _ = try await service.poll()

        // Assert: A's second call carries its token; B never received a token.
        let aTokens = zip(api.receivedCalendarIds, api.receivedSyncTokens).filter { $0.0 == "A" }.map(\.1)
        let bTokens = zip(api.receivedCalendarIds, api.receivedSyncTokens).filter { $0.0 == "B" }.map(\.1)
        XCTAssertEqual(aTokens, [nil, "token-a"])
        XCTAssertEqual(bTokens, [nil, nil])
    }

    func test_expiredSyncTokenDropsAndRetriesOnce() async throws {
        // Arrange
        let api = StubGoogleCalendarAPI()
        api.calendars = [GoogleCalendarListEntry(id: "A", summary: "A", primary: true, accessRole: "owner", backgroundColor: nil)]
        api.expireTokenOnce = ["A"]
        api.events["A"] = [timedEvent(id: "evt-a", title: "A event", startDate: fixedNow.addingTimeInterval(600))]
        api.defaultReminders["A"] = [GoogleCalendarDefaultReminder(method: "popup", minutes: 10)]
        let service = CalendarService(api: api, selectionStore: StubCalendarSelectionStore(), clock: { self.fixedNow })

        // Act
        let triggers = try await service.poll()

        // Assert: first call (410) then a retry without a token, and Triggers still resolve.
        XCTAssertEqual(api.receivedCalendarIds, ["A", "A"])
        XCTAssertEqual(api.receivedSyncTokens, [nil, nil])
        XCTAssertEqual(triggers.map(\.id), ["A#evt-a#10"])
    }

    func test_oneCalendarFailingDoesNotFailTheWholePoll() async throws {
        // Arrange: a persistently broken Calendar (e.g. access revoked) must not prevent
        // Triggers from every other selected Calendar from coming back.
        let api = StubGoogleCalendarAPI()
        api.calendars = [
            GoogleCalendarListEntry(id: "A", summary: "A", primary: true, accessRole: "owner", backgroundColor: nil),
            GoogleCalendarListEntry(id: "broken", summary: "Broken", primary: false, accessRole: "reader", backgroundColor: nil)
        ]
        api.alwaysFail = ["broken"]
        api.events["A"] = [timedEvent(id: "evt-a", title: "A event", startDate: fixedNow.addingTimeInterval(600))]
        api.defaultReminders["A"] = [GoogleCalendarDefaultReminder(method: "popup", minutes: 10)]
        let service = CalendarService(api: api, selectionStore: StubCalendarSelectionStore(), clock: { self.fixedNow })

        // Act
        let triggers = try await service.poll()

        // Assert
        XCTAssertEqual(triggers.map(\.id), ["A#evt-a#10"])
    }

    func test_authRevokedErrorPropagatesOutOfPoll() async throws {
        // Arrange: a dead refresh token breaks the whole session, not just one Calendar —
        // must propagate (unlike `test_oneCalendarFailingDoesNotFailTheWholePoll`).
        let api = StubGoogleCalendarAPI()
        api.authRevokedFor = ["primary"]
        let service = CalendarService(api: api, selectionStore: StubCalendarSelectionStore(), clock: { self.fixedNow })

        // Act / Assert
        do {
            _ = try await service.poll()
            XCTFail("expected AuthError.refreshTokenRevoked to propagate")
        } catch AuthError.refreshTokenRevoked {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func test_availableCalendarsMapsListCalendarsToDomainType() async throws {
        // Arrange (accessRole filtering itself is GoogleCalendarAPI's job, covered in GoogleCalendarAPITests)
        let api = StubGoogleCalendarAPI()
        api.calendars = [
            GoogleCalendarListEntry(id: "A", summary: "A", primary: true, accessRole: "owner", backgroundColor: nil),
            GoogleCalendarListEntry(id: "B", summary: "B", primary: false, accessRole: "reader", backgroundColor: nil)
        ]
        let service = CalendarService(api: api, selectionStore: StubCalendarSelectionStore())

        // Act
        let available = try await service.availableCalendars()

        // Assert
        XCTAssertEqual(available, [
            CalendarInfo(id: "A", title: "A", isPrimary: true),
            CalendarInfo(id: "B", title: "B", isPrimary: false)
        ])
    }
}
