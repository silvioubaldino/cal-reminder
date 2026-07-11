import Foundation

protocol CalendarServicing {
    /// Fetches upcoming Events for the next window, across every selected Calendar, and
    /// returns their resolved `[Trigger]` (RF-02/RF-03; RN-01/RN-02/RN-03).
    func poll() async throws -> [Trigger]

    /// Every Calendar in the connected account, for the "Calendars" menu (RF-10).
    func availableCalendars() async throws -> [CalendarInfo]
}

final class CalendarService: CalendarServicing {
    private static let pollWindow: TimeInterval = 2 * 60 * 60

    private let api: GoogleCalendarAPIProtocol
    private let selectionStore: CalendarSelectionStoring
    private let clock: () -> Date

    private var syncTokens: [String: String] = [:]
    private var cachedDefaultReminders: [String: [GoogleCalendarDefaultReminder]] = [:]

    init(
        api: GoogleCalendarAPIProtocol,
        selectionStore: CalendarSelectionStoring = UserDefaultsCalendarSelectionStore(),
        clock: @escaping () -> Date = Date.init
    ) {
        self.api = api
        self.selectionStore = selectionStore
        self.clock = clock
    }

    func availableCalendars() async throws -> [CalendarInfo] {
        try await api.listCalendars().map {
            CalendarInfo(id: $0.id, title: $0.summary, isPrimary: $0.primary ?? false)
        }
    }

    func poll() async throws -> [Trigger] {
        let calendars = try await api.listCalendars()
        let allIds = Set(calendars.map(\.id))
        let selectedIds = selectionStore.selectedCalendarIds?.intersection(allIds) ?? allIds
        print("[poll] \(calendars.count) available Calendars \(calendars.map(\.id)); stored selection=\(String(describing: selectionStore.selectedCalendarIds)); polling \(selectedIds)")

        var triggers: [Trigger] = []
        for calendarId in selectedIds {
            do {
                triggers += try await pollTriggers(calendarId: calendarId, retryOnExpiredToken: true)
            } catch {
                print("[poll] Calendar '\(calendarId)' failed: \(error) — skipping it for this Poll")
            }
        }
        return triggers
    }

    private func pollTriggers(calendarId: String, retryOnExpiredToken: Bool) async throws -> [Trigger] {
        let now = clock()
        let events: [GoogleEvent]
        let nextSyncToken: String?
        let responseDefaults: [GoogleCalendarDefaultReminder]?
        do {
            (events, nextSyncToken, responseDefaults) = try await api.listEvents(
                calendarId: calendarId,
                timeMin: now,
                timeMax: now.addingTimeInterval(Self.pollWindow),
                syncToken: syncTokens[calendarId]
            )
        } catch GoogleCalendarAPIError.unexpectedStatus(410) where retryOnExpiredToken {
            // Expired syncToken (RNF-06): drop it for this Calendar and retry once, full-window.
            syncTokens[calendarId] = nil
            return try await pollTriggers(calendarId: calendarId, retryOnExpiredToken: false)
        }

        if let nextSyncToken {
            syncTokens[calendarId] = nextSyncToken
        }
        // The calendar's default reminders arrive inline on every response; remember the
        // last non-nil value so resolution keeps working if a response ever omits them.
        if let responseDefaults {
            cachedDefaultReminders[calendarId] = responseDefaults
        }
        let defaults = cachedDefaultReminders[calendarId] ?? []

        return events.flatMap { event -> [Trigger] in
            guard let startDate = Self.parseDate(event.start.dateTime) else {
                print("[poll] skip '\(event.summary ?? "")' — no dateTime (all-day?) start=\(String(describing: event.start.dateTime))")
                return [] // all-day Event: no dateTime (RN-01)
            }

            let minutesList = ReminderResolver.popupReminderMinutes(for: event, calendarDefaults: defaults)
            print("[poll] event '\(event.summary ?? "")' start=\(startDate) useDefault=\(String(describing: event.reminders?.useDefault)) overrides=\(String(describing: event.reminders?.overrides)) → popup minutes=\(minutesList)")
            return minutesList.map { minutes in
                Trigger(
                    id: "\(calendarId)#\(event.id)#\(minutes)",
                    eventTitle: event.summary ?? "",
                    startDate: startDate,
                    fireDate: startDate.addingTimeInterval(-Double(minutes) * 60),
                    minutesBefore: minutes
                )
            }
        }
    }

    private static func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: string)
    }
}
