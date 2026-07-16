import Foundation

/// Resolves an Event's effective popup Reminders (RN-04): pure function, no I/O.
enum ReminderResolver {
    /// Fallback Reminder (RN-06) used when an Event resolves to no popup Reminder at all.
    static let defaultReminderMinutes = 5

    /// Minutes-before values of the Event's `popup` Reminders, honoring RN-04
    /// (`useDefault` → calendar defaults; otherwise → the Event's own overrides) and
    /// RN-06 (falls back to a single `defaultReminderMinutes` Reminder when that set is empty).
    static func popupReminderMinutes(
        for event: GoogleEvent,
        calendarDefaults: [GoogleCalendarDefaultReminder]
    ) -> [Int] {
        let useDefault = event.reminders?.useDefault ?? true

        let candidates: [(method: String, minutes: Int)]
        if useDefault {
            candidates = calendarDefaults.map { ($0.method, $0.minutes) }
        } else {
            candidates = (event.reminders?.overrides ?? []).map { ($0.method, $0.minutes) }
        }

        let minutes = candidates.filter { $0.method == "popup" }.map { $0.minutes }
        return minutes.isEmpty ? [defaultReminderMinutes] : minutes
    }
}
