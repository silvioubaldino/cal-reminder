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
    /// The primary calendar's default reminders, returned inline on every `events.list`
    /// response — used for Events with `reminders.useDefault == true` (RN-04).
    let defaultReminders: [GoogleCalendarDefaultReminder]?
}

/// A calendar's default reminder, used when an Event has `reminders.useDefault == true`.
struct GoogleCalendarDefaultReminder: Decodable {
    let method: String
    let minutes: Int
}

/// A raw `calendarList.list` item (RF-10).
struct GoogleCalendarListEntry: Decodable {
    let id: String
    let summary: String
    let primary: Bool?
    /// One of "owner" | "writer" | "reader" | "freeBusyReader"; only the first three can
    /// read Event details.
    let accessRole: String
    /// The Calendar Color (GLO), as hex — `"#0088aa"`. Optional: never assume the API
    /// sends it; a Calendar without one falls back to the Banner color preset (RF-13).
    let backgroundColor: String?
}

struct GoogleCalendarListResponse: Decodable {
    let items: [GoogleCalendarListEntry]
}

/// The domain view of a Calendar (GLO: Calendar), passed to the menu (RF-10). Named
/// `CalendarInfo` — not `Calendar` — to avoid colliding with `Foundation.Calendar`.
struct CalendarInfo: Identifiable, Equatable {
    let id: String
    let title: String
    let isPrimary: Bool
}
