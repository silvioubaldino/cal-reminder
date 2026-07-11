import Foundation

protocol CalendarServicing {
    /// Fetches upcoming Events for the next window and returns their resolved
    /// `[Trigger]` (RF-02/RF-03; RN-01/RN-02/RN-03).
    func poll() async throws -> [Trigger]
}

final class CalendarService: CalendarServicing {
    private static let pollWindow: TimeInterval = 2 * 60 * 60

    private let api: GoogleCalendarAPIProtocol
    private let clock: () -> Date

    private var syncToken: String?
    private var cachedDefaultReminders: [GoogleCalendarDefaultReminder]?

    init(api: GoogleCalendarAPIProtocol, clock: @escaping () -> Date = Date.init) {
        self.api = api
        self.clock = clock
    }

    func poll() async throws -> [Trigger] {
        let now = clock()
        let (events, nextSyncToken) = try await api.listEvents(
            timeMin: now,
            timeMax: now.addingTimeInterval(Self.pollWindow),
            syncToken: syncToken
        )
        if let nextSyncToken {
            syncToken = nextSyncToken
        }

        let defaults = try await defaultReminders()

        return events.flatMap { event -> [Trigger] in
            guard let startDate = Self.parseDate(event.start.dateTime) else {
                return [] // all-day Event: no dateTime (RN-01)
            }

            let minutesList = ReminderResolver.popupReminderMinutes(for: event, calendarDefaults: defaults)
            return minutesList.map { minutes in
                Trigger(
                    id: "\(event.id)#\(minutes)",
                    eventTitle: event.summary ?? "",
                    startDate: startDate,
                    fireDate: startDate.addingTimeInterval(-Double(minutes) * 60),
                    minutesBefore: minutes
                )
            }
        }
    }

    private func defaultReminders() async throws -> [GoogleCalendarDefaultReminder] {
        if let cachedDefaultReminders {
            return cachedDefaultReminders
        }
        let defaults = try await api.calendarDefaultReminders()
        cachedDefaultReminders = defaults
        return defaults
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
