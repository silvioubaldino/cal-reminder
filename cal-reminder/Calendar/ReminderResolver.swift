import Foundation

/// Resolves an Event's effective popup Reminders (RN-04, RN-06, RN-07): pure function, no I/O.
enum ReminderResolver {
    /// Fallback Reminder (RN-06) used when an Event resolves to no popup Reminder at all.
    static let defaultReminderMinutes = 5

    /// Minutes-before values of the Event's **effective** Reminders (RN-07): the union of the
    /// Event's own popup Reminders — honoring RN-04 (`useDefault` → calendar defaults; otherwise
    /// → the Event's own overrides) and RN-06 (falls back to `defaultReminderMinutes` when that
    /// set is empty), and only while `settings.inheritEventReminders` is on — with the Extra
    /// Reminders the user checked (RF-15).
    ///
    /// The inherited part keeps the API's order, so the default settings return exactly what the
    /// app returned before RF-15 existed. Extra Reminders follow, ascending, minus any minute the
    /// inherited part already produced — a Reminder never fires twice for the same minute.
    /// An empty result means the Event generates no Trigger at all.
    static func popupReminderMinutes(
        for event: GoogleEvent,
        calendarDefaults: [GoogleCalendarDefaultReminder],
        settings: ReminderSettings = .default
    ) -> [Int] {
        let inherited = settings.inheritEventReminders
            ? inheritedPopupMinutes(for: event, calendarDefaults: calendarDefaults)
            : []

        return inherited + settings.extraMinutes.subtracting(inherited).sorted()
    }

    /// The Event's own popup Reminders (RN-04) with RN-06's fallback applied.
    private static func inheritedPopupMinutes(
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
