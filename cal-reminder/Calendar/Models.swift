import Foundation

/// A raw Google Calendar `events.list` item (RF-02/RF-03).
struct GoogleEvent: Decodable {
    struct EventDateTime: Decodable {
        /// Present for timed Events (RN-01); nil for all-day Events.
        let dateTime: String?
        /// Present for all-day Events; nil for timed Events.
        let date: String?
    }

    struct ReminderOverride: Decodable {
        let method: String
        let minutes: Int
    }

    struct Reminders: Decodable {
        let useDefault: Bool
        let overrides: [ReminderOverride]?
    }

    let id: String
    let summary: String?
    let start: EventDateTime
    let reminders: Reminders?
}

struct GoogleEventsListResponse: Decodable {
    let items: [GoogleEvent]
    let nextSyncToken: String?
}

/// A calendar's default reminder, used when an Event has `reminders.useDefault == true`.
struct GoogleCalendarDefaultReminder: Decodable {
    let method: String
    let minutes: Int
}

struct GoogleCalendarEntry: Decodable {
    let defaultReminders: [GoogleCalendarDefaultReminder]
}
