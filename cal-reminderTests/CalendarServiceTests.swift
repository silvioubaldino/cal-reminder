import XCTest
@testable import cal_reminder

private final class StubGoogleCalendarAPI: GoogleCalendarAPIProtocol {
    var calendars: [GoogleCalendarListEntry] = [
        GoogleCalendarListEntry(id: "primary", summary: "Primary", primary: true, accessRole: "owner", backgroundColor: nil)
    ]
    var events: [String: [GoogleEvent]] = [:]
    var nextSyncTokens: [String: String] = [:]
    var defaultReminders: [String: [GoogleCalendarDefaultReminder]?] = [:]
    var expireTokenOnce: Set<String> = []
    var alwaysFail: Set<String> = []
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

private final class StubReminderSettingsStore: ReminderSettingsStoring {
    var settings: ReminderSettings
    init(_ settings: ReminderSettings = .default) {
        self.settings = settings
    }
}

private final class StubCalendarSelectionStore: CalendarSelectionStoring {
    var selectedCalendarIds: Set<String>?
    init(selectedCalendarIds: Set<String>? = nil) {
        self.selectedCalendarIds = selectedCalendarIds
    }
}

final class CalendarServiceTests: XCTestCase {
    private let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

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
            status: "confirmed",
            reminders: .init(useDefault: useDefault, overrides: overrides)
        )
    }

    private func allDayEvent(id: String) -> GoogleEvent {
        GoogleEvent(
            id: id,
            summary: "Holiday",
            start: .init(dateTime: nil, date: "2027-01-16"),
            status: "confirmed",
            reminders: nil
        )
    }

    /// A cancelled Event as it arrives in an incremental delta (AYD-011): only `id` and
    /// `status`, no `start`.
    private func cancelledEvent(id: String) -> GoogleEvent {
        GoogleEvent(id: id, summary: nil, start: nil, status: "cancelled", reminders: nil)
    }

    func test_onlyTimedEventsProduceTriggers() async throws {
        let api = StubGoogleCalendarAPI()
        api.events["primary"] = [
            timedEvent(id: "evt-timed", title: "Standup", startDate: fixedNow.addingTimeInterval(600)),
            allDayEvent(id: "evt-allday")
        ]
        api.defaultReminders["primary"] = [GoogleCalendarDefaultReminder(method: "popup", minutes: 10)]
        let service = CalendarService(api: api, accountId: "acct1", selectionStore: StubCalendarSelectionStore(), reminderSettingsStore: StubReminderSettingsStore(), clock: { self.fixedNow })

        let triggers = try await service.poll()

        XCTAssertEqual(triggers.count, 1)
        XCTAssertEqual(triggers.first?.id, "acct1#primary#evt-timed#10")
    }

    func test_resolvesRemindersPerRN04() async throws {
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
        let service = CalendarService(api: api, accountId: "acct1", selectionStore: StubCalendarSelectionStore(), reminderSettingsStore: StubReminderSettingsStore(), clock: { self.fixedNow })

        let triggers = try await service.poll()

        XCTAssertTrue(triggers.contains { $0.id == "acct1#primary#evt-default#15" })
        XCTAssertTrue(triggers.contains { $0.id == "acct1#primary#evt-override#5" })
        XCTAssertFalse(triggers.contains { $0.id == "acct1#primary#evt-override#60" })
    }

    func test_extraReminderProducesItsOwnTriggerAlongsideTheEventsOwn() async throws {
        // Arrange — "1 minute before" checked on top of the Event's own 10-minute Reminder (RF-15)
        let api = StubGoogleCalendarAPI()
        let start = fixedNow.addingTimeInterval(3600)
        api.events["primary"] = [timedEvent(id: "evt1", title: "Standup", startDate: start)]
        api.defaultReminders["primary"] = [GoogleCalendarDefaultReminder(method: "popup", minutes: 10)]
        let service = CalendarService(
            api: api,
            accountId: "acct1",
            selectionStore: StubCalendarSelectionStore(),
            reminderSettingsStore: StubReminderSettingsStore(ReminderSettings(inheritEventReminders: true, extraMinutes: [1])),
            clock: { self.fixedNow }
        )

        // Act
        let triggers = try await service.poll()

        // Assert — distinct dedupe ids (RN-03), each firing at its own offset
        XCTAssertEqual(triggers.count, 2)
        XCTAssertEqual(Set(triggers.map(\.id)), ["acct1#primary#evt1#10", "acct1#primary#evt1#1"])
        XCTAssertEqual(
            triggers.first { $0.minutesBefore == 1 }?.fireDate,
            start.addingTimeInterval(-60)
        )
    }

    func test_noReminderSelectedProducesNoTriggerAtAll() async throws {
        // Arrange — the empty selection (RN-07)
        let api = StubGoogleCalendarAPI()
        api.events["primary"] = [
            timedEvent(id: "evt1", title: "Standup", startDate: fixedNow.addingTimeInterval(3600))
        ]
        api.defaultReminders["primary"] = [GoogleCalendarDefaultReminder(method: "popup", minutes: 10)]
        let service = CalendarService(
            api: api,
            accountId: "acct1",
            selectionStore: StubCalendarSelectionStore(),
            reminderSettingsStore: StubReminderSettingsStore(ReminderSettings(inheritEventReminders: false, extraMinutes: [])),
            clock: { self.fixedNow }
        )

        // Act
        let triggers = try await service.poll()

        // Assert
        XCTAssertTrue(triggers.isEmpty)
    }

    func test_oneTriggerPerPopupReminderWithCorrectFireDate() async throws {
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
        let service = CalendarService(api: api, accountId: "acct1", selectionStore: StubCalendarSelectionStore(), reminderSettingsStore: StubReminderSettingsStore(), clock: { self.fixedNow })

        let triggers = try await service.poll()

        XCTAssertEqual(triggers.count, 2)
        let byMinutes = Dictionary(uniqueKeysWithValues: triggers.map { ($0.minutesBefore, $0) })
        XCTAssertEqual(byMinutes[10]?.id, "acct1#primary#evt1#10")
        XCTAssertEqual(byMinutes[10]?.fireDate, start.addingTimeInterval(-10 * 60))
        XCTAssertEqual(byMinutes[2]?.id, "acct1#primary#evt1#2")
        XCTAssertEqual(byMinutes[2]?.fireDate, start.addingTimeInterval(-2 * 60))
    }

    func test_usesSyncTokenOnSubsequentPolls() async throws {
        let api = StubGoogleCalendarAPI()
        api.nextSyncTokens["primary"] = "token-abc"
        let service = CalendarService(api: api, accountId: "acct1", selectionStore: StubCalendarSelectionStore(), reminderSettingsStore: StubReminderSettingsStore(), clock: { self.fixedNow })

        _ = try await service.poll()
        _ = try await service.poll()

        XCTAssertEqual(api.receivedSyncTokens, [nil, "token-abc"])
    }

    func test_fullResyncPollDropsTheStoredSyncToken() async throws {
        let api = StubGoogleCalendarAPI()
        api.nextSyncTokens["primary"] = "token-abc"
        let service = CalendarService(api: api, accountId: "acct1", selectionStore: StubCalendarSelectionStore(), reminderSettingsStore: StubReminderSettingsStore(), clock: { self.fixedNow })

        _ = try await service.poll()
        _ = try await service.poll(fullResync: true)
        _ = try await service.poll()

        XCTAssertEqual(api.receivedSyncTokens, [nil, nil, "token-abc"])
    }

    func test_cancelledEventInDeltaDoesNotBreakPollAndSyncTokenIsStored() async throws {
        // Arrange — SPEC-021 Slice 1: a cancelled Event in a delta carries no `start` and used
        // to throw while decoding, stranding that Calendar's syncToken forever (AYD-011).
        let api = StubGoogleCalendarAPI()
        api.events["primary"] = [cancelledEvent(id: "evt-gone")]
        api.nextSyncTokens["primary"] = "token-after-delta"
        let service = CalendarService(api: api, accountId: "acct1", selectionStore: StubCalendarSelectionStore(), reminderSettingsStore: StubReminderSettingsStore(), clock: { self.fixedNow })

        // Act
        let triggers = try await service.poll()

        // Assert
        XCTAssertTrue(triggers.isEmpty)
        _ = try await service.poll()
        XCTAssertEqual(api.receivedSyncTokens, [nil, "token-after-delta"], "the syncToken from the response that carried the cancelled Event must still be stored")
    }

    func test_fullResyncKeepsTheCachedDefaultReminders() async throws {
        let api = StubGoogleCalendarAPI()
        api.defaultReminders["primary"] = [GoogleCalendarDefaultReminder(method: "popup", minutes: 10)]
        let service = CalendarService(api: api, accountId: "acct1", selectionStore: StubCalendarSelectionStore(), reminderSettingsStore: StubReminderSettingsStore(), clock: { self.fixedNow })
        _ = try await service.poll()

        api.defaultReminders.updateValue(nil, forKey: "primary")
        api.events["primary"] = [timedEvent(id: "evt1", title: "Standup", startDate: fixedNow.addingTimeInterval(600))]
        let triggers = try await service.poll(fullResync: true)

        XCTAssertEqual(triggers.first?.id, "acct1#primary#evt1#10")
    }

    func test_remembersDefaultRemindersWhenResponseOmitsThem() async throws {
        let api = StubGoogleCalendarAPI()
        api.defaultReminders["primary"] = [GoogleCalendarDefaultReminder(method: "popup", minutes: 10)]
        let service = CalendarService(api: api, accountId: "acct1", selectionStore: StubCalendarSelectionStore(), reminderSettingsStore: StubReminderSettingsStore(), clock: { self.fixedNow })

        _ = try await service.poll()
        api.defaultReminders.updateValue(nil, forKey: "primary")
        api.events["primary"] = [timedEvent(id: "evt1", title: "Standup", startDate: fixedNow.addingTimeInterval(600))]
        let triggers = try await service.poll()

        XCTAssertEqual(triggers.first?.id, "acct1#primary#evt1#10")
    }

    func test_stampsEachCalendarsColorOnItsTriggers() async throws {
        let api = StubGoogleCalendarAPI()
        api.calendars = [
            GoogleCalendarListEntry(id: "A", summary: "A", primary: true, accessRole: "owner", backgroundColor: "#0b8043"),
            GoogleCalendarListEntry(id: "B", summary: "B", primary: false, accessRole: "reader", backgroundColor: nil)
        ]
        api.events["A"] = [timedEvent(id: "evt-a", title: "A event", startDate: fixedNow.addingTimeInterval(600))]
        api.events["B"] = [timedEvent(id: "evt-b", title: "B event", startDate: fixedNow.addingTimeInterval(600))]
        api.defaultReminders["A"] = [GoogleCalendarDefaultReminder(method: "popup", minutes: 10)]
        api.defaultReminders["B"] = [GoogleCalendarDefaultReminder(method: "popup", minutes: 10)]
        let service = CalendarService(api: api, accountId: "acct1", selectionStore: StubCalendarSelectionStore(), reminderSettingsStore: StubReminderSettingsStore(), clock: { self.fixedNow })

        let triggers = try await service.poll()

        let triggerA = try XCTUnwrap(triggers.first(where: { $0.id == "acct1#A#evt-a#10" }))
        let triggerB = try XCTUnwrap(triggers.first(where: { $0.id == "acct1#B#evt-b#10" }))
        XCTAssertEqual(triggerA.calendarColorHex, "#0b8043")
        XCTAssertNil(triggerB.calendarColorHex)
    }

    func test_defaultSelectionPollsEveryCalendar() async throws {
        let api = StubGoogleCalendarAPI()
        api.calendars = [
            GoogleCalendarListEntry(id: "A", summary: "A", primary: true, accessRole: "owner", backgroundColor: nil),
            GoogleCalendarListEntry(id: "B", summary: "B", primary: false, accessRole: "reader", backgroundColor: nil)
        ]
        api.events["A"] = [timedEvent(id: "evt-a", title: "A event", startDate: fixedNow.addingTimeInterval(600))]
        api.events["B"] = [timedEvent(id: "evt-b", title: "B event", startDate: fixedNow.addingTimeInterval(600))]
        api.defaultReminders["A"] = [GoogleCalendarDefaultReminder(method: "popup", minutes: 10)]
        api.defaultReminders["B"] = [GoogleCalendarDefaultReminder(method: "popup", minutes: 10)]
        let service = CalendarService(api: api, accountId: "acct1", selectionStore: StubCalendarSelectionStore(selectedCalendarIds: nil), reminderSettingsStore: StubReminderSettingsStore(), clock: { self.fixedNow })

        let triggers = try await service.poll()

        XCTAssertEqual(Set(api.receivedCalendarIds), ["A", "B"])
        XCTAssertEqual(Set(triggers.map(\.id)), ["acct1#A#evt-a#10", "acct1#B#evt-b#10"])
    }

    func test_onlySelectedCalendarsArePolled() async throws {
        let api = StubGoogleCalendarAPI()
        api.calendars = [
            GoogleCalendarListEntry(id: "A", summary: "A", primary: true, accessRole: "owner", backgroundColor: nil),
            GoogleCalendarListEntry(id: "B", summary: "B", primary: false, accessRole: "reader", backgroundColor: nil)
        ]
        api.events["A"] = [timedEvent(id: "evt-a", title: "A event", startDate: fixedNow.addingTimeInterval(600))]
        api.events["B"] = [timedEvent(id: "evt-b", title: "B event", startDate: fixedNow.addingTimeInterval(600))]
        api.defaultReminders["A"] = [GoogleCalendarDefaultReminder(method: "popup", minutes: 10)]
        api.defaultReminders["B"] = [GoogleCalendarDefaultReminder(method: "popup", minutes: 10)]
        let service = CalendarService(api: api, accountId: "acct1", selectionStore: StubCalendarSelectionStore(selectedCalendarIds: ["A"]), reminderSettingsStore: StubReminderSettingsStore(), clock: { self.fixedNow })

        let triggers = try await service.poll()

        XCTAssertEqual(api.receivedCalendarIds, ["A"])
        XCTAssertEqual(triggers.map(\.id), ["acct1#A#evt-a#10"])
    }

    func test_dedupeIdsArePrefixedWithCalendarId() async throws {
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
        let service = CalendarService(api: api, accountId: "acct1", selectionStore: StubCalendarSelectionStore(), reminderSettingsStore: StubReminderSettingsStore(), clock: { self.fixedNow })

        let triggers = try await service.poll()

        XCTAssertEqual(triggers.count, 2)
        XCTAssertEqual(Set(triggers.map(\.id)), ["acct1#A#\(sharedEventId)#10", "acct1#B#\(sharedEventId)#10"])
    }

    func test_dedupeIdsArePrefixedWithAccountId() async throws {
        let api = StubGoogleCalendarAPI()
        api.events["primary"] = [timedEvent(id: "evt1", title: "Standup", startDate: fixedNow.addingTimeInterval(600))]
        api.defaultReminders["primary"] = [GoogleCalendarDefaultReminder(method: "popup", minutes: 10)]
        let serviceA = CalendarService(api: api, accountId: "acctA", selectionStore: StubCalendarSelectionStore(), reminderSettingsStore: StubReminderSettingsStore(), clock: { self.fixedNow })
        let serviceB = CalendarService(api: api, accountId: "acctB", selectionStore: StubCalendarSelectionStore(), reminderSettingsStore: StubReminderSettingsStore(), clock: { self.fixedNow })

        let triggersA = try await serviceA.poll()
        let triggersB = try await serviceB.poll()

        XCTAssertEqual(triggersA.map(\.id), ["acctA#primary#evt1#10"])
        XCTAssertEqual(triggersB.map(\.id), ["acctB#primary#evt1#10"])
    }

    func test_perCalendarSyncTokenIsolation() async throws {
        let api = StubGoogleCalendarAPI()
        api.calendars = [
            GoogleCalendarListEntry(id: "A", summary: "A", primary: true, accessRole: "owner", backgroundColor: nil),
            GoogleCalendarListEntry(id: "B", summary: "B", primary: false, accessRole: "reader", backgroundColor: nil)
        ]
        api.nextSyncTokens["A"] = "token-a"
        let service = CalendarService(api: api, accountId: "acct1", selectionStore: StubCalendarSelectionStore(), reminderSettingsStore: StubReminderSettingsStore(), clock: { self.fixedNow })

        _ = try await service.poll()
        _ = try await service.poll()

        let aTokens = zip(api.receivedCalendarIds, api.receivedSyncTokens).filter { $0.0 == "A" }.map(\.1)
        let bTokens = zip(api.receivedCalendarIds, api.receivedSyncTokens).filter { $0.0 == "B" }.map(\.1)
        XCTAssertEqual(aTokens, [nil, "token-a"])
        XCTAssertEqual(bTokens, [nil, nil])
    }

    func test_expiredSyncTokenDropsAndRetriesOnce() async throws {
        let api = StubGoogleCalendarAPI()
        api.calendars = [GoogleCalendarListEntry(id: "A", summary: "A", primary: true, accessRole: "owner", backgroundColor: nil)]
        api.expireTokenOnce = ["A"]
        api.events["A"] = [timedEvent(id: "evt-a", title: "A event", startDate: fixedNow.addingTimeInterval(600))]
        api.defaultReminders["A"] = [GoogleCalendarDefaultReminder(method: "popup", minutes: 10)]
        let service = CalendarService(api: api, accountId: "acct1", selectionStore: StubCalendarSelectionStore(), reminderSettingsStore: StubReminderSettingsStore(), clock: { self.fixedNow })

        let triggers = try await service.poll()

        XCTAssertEqual(api.receivedCalendarIds, ["A", "A"])
        XCTAssertEqual(api.receivedSyncTokens, [nil, nil])
        XCTAssertEqual(triggers.map(\.id), ["acct1#A#evt-a#10"])
    }

    func test_oneCalendarFailingDoesNotFailTheWholePoll() async throws {
        let api = StubGoogleCalendarAPI()
        api.calendars = [
            GoogleCalendarListEntry(id: "A", summary: "A", primary: true, accessRole: "owner", backgroundColor: nil),
            GoogleCalendarListEntry(id: "broken", summary: "Broken", primary: false, accessRole: "reader", backgroundColor: nil)
        ]
        api.alwaysFail = ["broken"]
        api.events["A"] = [timedEvent(id: "evt-a", title: "A event", startDate: fixedNow.addingTimeInterval(600))]
        api.defaultReminders["A"] = [GoogleCalendarDefaultReminder(method: "popup", minutes: 10)]
        let service = CalendarService(api: api, accountId: "acct1", selectionStore: StubCalendarSelectionStore(), reminderSettingsStore: StubReminderSettingsStore(), clock: { self.fixedNow })

        let triggers = try await service.poll()

        XCTAssertEqual(triggers.map(\.id), ["acct1#A#evt-a#10"])
    }

    func test_authRevokedErrorPropagatesOutOfPoll() async throws {
        let api = StubGoogleCalendarAPI()
        api.authRevokedFor = ["primary"]
        let service = CalendarService(api: api, accountId: "acct1", selectionStore: StubCalendarSelectionStore(), reminderSettingsStore: StubReminderSettingsStore(), clock: { self.fixedNow })

        do {
            _ = try await service.poll()
            XCTFail("expected AuthError.refreshTokenRevoked to propagate")
        } catch AuthError.refreshTokenRevoked {
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func test_availableCalendarsMapsListCalendarsToDomainType() async throws {
        let api = StubGoogleCalendarAPI()
        api.calendars = [
            GoogleCalendarListEntry(id: "A", summary: "A", primary: true, accessRole: "owner", backgroundColor: nil),
            GoogleCalendarListEntry(id: "B", summary: "B", primary: false, accessRole: "reader", backgroundColor: nil)
        ]
        let service = CalendarService(api: api, accountId: "acct1", selectionStore: StubCalendarSelectionStore(), reminderSettingsStore: StubReminderSettingsStore())

        let available = try await service.availableCalendars()

        XCTAssertEqual(available, [
            CalendarInfo(id: "A", title: "A", isPrimary: true),
            CalendarInfo(id: "B", title: "B", isPrimary: false)
        ])
    }
}
