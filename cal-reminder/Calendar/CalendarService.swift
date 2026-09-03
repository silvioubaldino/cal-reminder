import Foundation

protocol CalendarServicing {
    /// Fetches upcoming Events for the next window, across every selected Calendar, and
    /// returns their resolved `[Trigger]` (RF-02/RF-03; RN-01/RN-02/RN-03).
    ///
    /// `fullResync` discards the stored `syncToken`s first, so the fetch returns the whole
    /// window instead of the delta since the last Poll — what the manual "Refresh now"
    /// (RF-12) needs to rebuild a stale state (SPEC-013). The background Poll leaves it
    /// `false` and stays incremental (RNF-06).
    func poll(fullResync: Bool) async throws -> [Trigger]

    /// Every Calendar in the connected account, for the "Calendars" menu (RF-10).
    func availableCalendars() async throws -> [CalendarInfo]
}

extension CalendarServicing {
    /// The incremental Poll — the default everywhere except the manual refresh.
    func poll() async throws -> [Trigger] {
        try await poll(fullResync: false)
    }
}

final class CalendarService: CalendarServicing {
    private static let pollWindow: TimeInterval = 2 * 60 * 60

    private let api: GoogleCalendarAPIProtocol
    /// The connected Account this service polls on behalf of — prefixed onto every
    /// Trigger's dedupe id (RN-03), so a Calendar id shared between two Accounts can never
    /// collide (AYD-007).
    private let accountId: String
    private let selectionStore: CalendarSelectionStoring
    private let clock: () -> Date

    private var syncTokens: [String: String] = [:]
    private var cachedDefaultReminders: [String: [GoogleCalendarDefaultReminder]] = [:]

    init(
        api: GoogleCalendarAPIProtocol,
        accountId: String,
        selectionStore: CalendarSelectionStoring,
        clock: @escaping () -> Date = Date.init
    ) {
        self.api = api
        self.accountId = accountId
        self.selectionStore = selectionStore
        self.clock = clock
    }

    func availableCalendars() async throws -> [CalendarInfo] {
        try await api.listCalendars().map {
            CalendarInfo(id: $0.id, title: $0.summary, isPrimary: $0.primary ?? false)
        }
    }

    func poll(fullResync: Bool) async throws -> [Trigger] {
        if fullResync {
            // Drop the sync state so every Calendar goes back through the timeMin/timeMax
            // branch (SPEC-013). `cachedDefaultReminders` is kept: it isn't sync state, and
            // the full fetch refreshes it inline anyway (RN-04).
            syncTokens.removeAll()
        }
        let calendars = try await api.listCalendars()
        let allIds = Set(calendars.map(\.id))
        let selectedIds = selectionStore.selectedCalendarIds?.intersection(allIds) ?? allIds
        print("[poll] \(calendars.count) available Calendars \(calendars.map(\.id)); stored selection=\(String(describing: selectionStore.selectedCalendarIds)); polling \(selectedIds)")

        // The Calendar Color rides along on the list the Poll already fetches (RF-13) —
        // no extra request; Calendars without one map to nil and fall back to the preset.
        let colorsById = Dictionary(calendars.map { ($0.id, $0.backgroundColor) }, uniquingKeysWith: { _, last in last })

        var triggers: [Trigger] = []
        for calendarId in selectedIds {
            do {
                triggers += try await pollTriggers(
                    calendarId: calendarId,
                    calendarColorHex: colorsById[calendarId] ?? nil,
                    retryOnExpiredToken: true
                )
            } catch AuthError.refreshTokenRevoked {
                // The session itself is dead, not just this Calendar — propagate so the
                // AppCoordinator can drop to `.needsReauth` instead of silently skipping it.
                throw AuthError.refreshTokenRevoked
            } catch {
                print("[poll] Calendar '\(calendarId)' failed: \(error) — skipping it for this Poll")
            }
        }
        return triggers
    }

    private func pollTriggers(calendarId: String, calendarColorHex: String?, retryOnExpiredToken: Bool) async throws -> [Trigger] {
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
            return try await pollTriggers(calendarId: calendarId, calendarColorHex: calendarColorHex, retryOnExpiredToken: false)
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
