import Foundation

protocol CalendarServicing {
    func poll(fullResync: Bool) async throws -> [Trigger]

    func availableCalendars() async throws -> [CalendarInfo]
}

extension CalendarServicing {
    func poll() async throws -> [Trigger] {
        try await poll(fullResync: false)
    }
}

final class CalendarService: CalendarServicing {
    private static let pollWindow: TimeInterval = 2 * 60 * 60

    private let api: GoogleCalendarAPIProtocol
    private let accountId: String
    private let selectionStore: CalendarSelectionStoring
    private let reminderSettingsStore: ReminderSettingsStoring
    private let clock: () -> Date

    private var syncTokens: [String: String] = [:]
    private var cachedDefaultReminders: [String: [GoogleCalendarDefaultReminder]] = [:]

    init(
        api: GoogleCalendarAPIProtocol,
        accountId: String,
        selectionStore: CalendarSelectionStoring,
        reminderSettingsStore: ReminderSettingsStoring = UserDefaultsReminderSettingsStore(),
        clock: @escaping () -> Date = Date.init
    ) {
        self.api = api
        self.accountId = accountId
        self.selectionStore = selectionStore
        self.reminderSettingsStore = reminderSettingsStore
        self.clock = clock
    }

    func availableCalendars() async throws -> [CalendarInfo] {
        try await api.listCalendars().map {
            CalendarInfo(id: $0.id, title: $0.summary, isPrimary: $0.primary ?? false)
        }
    }

    func poll(fullResync: Bool) async throws -> [Trigger] {
        if fullResync {
            syncTokens.removeAll()
        }
        let calendars = try await api.listCalendars()
        let allIds = Set(calendars.map(\.id))
        let selectedIds = selectionStore.selectedCalendarIds?.intersection(allIds) ?? allIds
        print("[poll] \(calendars.count) available Calendars \(calendars.map(\.id)); stored selection=\(String(describing: selectionStore.selectedCalendarIds)); polling \(selectedIds)")

        let colorsById = Dictionary(calendars.map { ($0.id, $0.backgroundColor) }, uniquingKeysWith: { _, last in last })
        // Read once per Poll, not at init: a Reminder-selection change (RF-15) must be picked
        // up by the very next Poll — which is the full resync the change itself triggers.
        let reminderSettings = reminderSettingsStore.settings

        var triggers: [Trigger] = []
        for calendarId in selectedIds {
            do {
                triggers += try await pollTriggers(
                    calendarId: calendarId,
                    calendarColorHex: colorsById[calendarId] ?? nil,
                    reminderSettings: reminderSettings,
                    retryOnExpiredToken: true
                )
            } catch AuthError.refreshTokenRevoked {
                throw AuthError.refreshTokenRevoked
            } catch {
                print("[poll] Calendar '\(calendarId)' failed: \(error) — skipping it for this Poll")
            }
        }
        return triggers
    }

    private func pollTriggers(
        calendarId: String,
        calendarColorHex: String?,
        reminderSettings: ReminderSettings,
        retryOnExpiredToken: Bool
    ) async throws -> [Trigger] {
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
            syncTokens[calendarId] = nil
            return try await pollTriggers(
                calendarId: calendarId,
                calendarColorHex: calendarColorHex,
                reminderSettings: reminderSettings,
                retryOnExpiredToken: false
            )
        }

        if let nextSyncToken {
            syncTokens[calendarId] = nextSyncToken
        }
        if let responseDefaults {
            cachedDefaultReminders[calendarId] = responseDefaults
        }
        let defaults = cachedDefaultReminders[calendarId] ?? []

        return events.flatMap { event -> [Trigger] in
            guard let startDate = Self.parseDate(event.start.dateTime) else {
                print("[poll] skip '\(event.summary ?? "")' — no dateTime (all-day?) start=\(String(describing: event.start.dateTime))")
                return []
            }

            let minutesList = ReminderResolver.popupReminderMinutes(
                for: event,
                calendarDefaults: defaults,
                settings: reminderSettings
            )
            print("[poll] event '\(event.summary ?? "")' start=\(startDate) useDefault=\(String(describing: event.reminders?.useDefault)) overrides=\(String(describing: event.reminders?.overrides)) → popup minutes=\(minutesList)")
            return minutesList.map { minutes in
                Trigger(
                    id: "\(accountId)#\(calendarId)#\(event.id)#\(minutes)",
                    eventTitle: event.summary ?? "",
                    startDate: startDate,
                    fireDate: startDate.addingTimeInterval(-Double(minutes) * 60),
                    minutesBefore: minutes,
                    calendarColorHex: calendarColorHex
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
