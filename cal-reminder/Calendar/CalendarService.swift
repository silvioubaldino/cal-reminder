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
    private static let pollWindow: TimeInterval = 48 * 60 * 60
    private static let fullResyncInterval: TimeInterval = 6 * 60 * 60

    private let api: GoogleCalendarAPIProtocol
    private let accountId: String
    private let selectionStore: CalendarSelectionStoring
    private let reminderSettingsStore: ReminderSettingsStoring
    private let clock: () -> Date

    private var syncTokens: [String: String] = [:]
    private var cachedDefaultReminders: [String: [GoogleCalendarDefaultReminder]] = [:]
    private var replica: [String: [String: GoogleEvent]] = [:]
    private var lastFullSync: Date?

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
        let now = clock()
        let calendars = try await api.listCalendars()
        let allIds = Set(calendars.map(\.id))
        let selectedIds = selectionStore.selectedCalendarIds?.intersection(allIds) ?? allIds
        print("[poll] \(calendars.count) available Calendars \(calendars.map(\.id)); stored selection=\(String(describing: selectionStore.selectedCalendarIds)); polling \(selectedIds)")

        let mustFullSync = fullResync
            || (lastFullSync.map { now.timeIntervalSince($0) >= Self.fullResyncInterval } ?? true)
        if mustFullSync {
            syncTokens.removeAll()
            lastFullSync = now
        }

        let colorsById = Dictionary(calendars.map { ($0.id, $0.backgroundColor) }, uniquingKeysWith: { _, last in last })
        // Read once per Poll, not at init: a Reminder-selection change (RF-15) must be picked
        // up by the very next Poll — which is the full resync the change itself triggers.
        let reminderSettings = reminderSettingsStore.settings
        let windowEnd = now.addingTimeInterval(Self.pollWindow)

        for calendarId in selectedIds {
            do {
                try await fetchAndApply(calendarId: calendarId, windowEnd: windowEnd, retryOnExpiredToken: true)
            } catch AuthError.refreshTokenRevoked {
                throw AuthError.refreshTokenRevoked
            } catch {
                print("[poll] Calendar '\(calendarId)' failed: \(error) — skipping it for this Poll; its replica (if any) is kept as-is")
            }
        }

        return deriveTriggers(selectedIds: selectedIds, colorsById: colorsById, reminderSettings: reminderSettings, now: now)
    }

    private func fetchAndApply(calendarId: String, windowEnd: Date, retryOnExpiredToken: Bool) async throws {
        let now = clock()
        let isFullSync = syncTokens[calendarId] == nil
        let events: [GoogleEvent]
        let nextSyncToken: String?
        let responseDefaults: [GoogleCalendarDefaultReminder]?
        do {
            (events, nextSyncToken, responseDefaults) = try await api.listEvents(
                calendarId: calendarId,
                timeMin: now,
                timeMax: windowEnd,
                syncToken: syncTokens[calendarId]
            )
        } catch GoogleCalendarAPIError.unexpectedStatus(410) where retryOnExpiredToken {
            syncTokens[calendarId] = nil
            return try await fetchAndApply(calendarId: calendarId, windowEnd: windowEnd, retryOnExpiredToken: false)
        }

        if isFullSync {
            var fresh: [String: GoogleEvent] = [:]
            for event in events where event.status != "cancelled" {
                fresh[event.id] = event
            }
            replica[calendarId] = fresh
        } else {
            var calendarReplica = replica[calendarId] ?? [:]
            for event in events {
                if event.status == "cancelled" {
                    calendarReplica.removeValue(forKey: event.id)
                } else {
                    calendarReplica[event.id] = event
                }
            }
            replica[calendarId] = calendarReplica
        }

        if let nextSyncToken {
            syncTokens[calendarId] = nextSyncToken
        }
        if let responseDefaults {
            cachedDefaultReminders[calendarId] = responseDefaults
        }
    }

    private func deriveTriggers(
        selectedIds: Set<String>,
        colorsById: [String: String?],
        reminderSettings: ReminderSettings,
        now: Date
    ) -> [Trigger] {
        var triggers: [Trigger] = []
        for calendarId in selectedIds {
            guard let events = replica[calendarId] else { continue }
            let defaults = cachedDefaultReminders[calendarId] ?? []
            var prunedEvents = events

            for (eventId, event) in events {
                guard let startDate = Self.parseDate(event.start?.dateTime) else {
                    print("[poll] skip '\(event.summary ?? "")' — no dateTime (all-day?) start=\(String(describing: event.start?.dateTime))")
                    continue
                }
                guard startDate >= now else {
                    prunedEvents.removeValue(forKey: eventId)
                    continue
                }

                let minutesList = ReminderResolver.popupReminderMinutes(
                    for: event,
                    calendarDefaults: defaults,
                    settings: reminderSettings
                )
                print("[poll] event '\(event.summary ?? "")' start=\(startDate) useDefault=\(String(describing: event.reminders?.useDefault)) overrides=\(String(describing: event.reminders?.overrides)) → popup minutes=\(minutesList)")
                for minutes in minutesList {
                    triggers.append(Trigger(
                        id: "\(accountId)#\(calendarId)#\(eventId)#\(minutes)",
                        eventTitle: event.summary ?? "",
                        startDate: startDate,
                        fireDate: startDate.addingTimeInterval(-Double(minutes) * 60),
                        minutesBefore: minutes,
                        calendarColorHex: colorsById[calendarId] ?? nil,
                        accountId: accountId
                    ))
                }
            }

            replica[calendarId] = prunedEvents
        }
        return triggers
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
