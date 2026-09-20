import Foundation

/// Which Reminder produced a Trigger — reported alongside `planes_flown` (RF-17) so the
/// Project Service can tell event-driven flights apart from the menu bar's test animation.
enum TriggerOrigin: String, Codable, Equatable, Sendable {
    case eventReminder = "event_reminder"
    case extraReminder = "extra_reminder"
    case testAnimation = "test_animation"
}

/// The computed moment to fire the animation: `Event start − Reminder minutes` (GLO: Trigger).
struct Trigger: Identifiable, Equatable, Sendable {
    /// Dedupe key: "<accountId>#<calendarId>#<eventId>#<minutes>" (RN-03).
    let id: String
    let eventTitle: String
    let startDate: Date
    let fireDate: Date
    let minutesBefore: Int
    /// The Calendar Color (GLO) of the Calendar this Trigger came from, as hex, so the
    /// Banner can be painted with it at fire time (RF-13) — minutes to hours after the
    /// Poll that resolved it. Kept as a String, not an `NSColor`: the domain model stays
    /// free of AppKit. `nil` when the Calendar has no color, or for the test animation.
    let calendarColorHex: String?
    let accountId: String
    let origin: TriggerOrigin

    init(
        id: String,
        eventTitle: String,
        startDate: Date,
        fireDate: Date,
        minutesBefore: Int,
        calendarColorHex: String? = nil,
        accountId: String,
        origin: TriggerOrigin = .eventReminder
    ) {
        self.id = id
        self.eventTitle = eventTitle
        self.startDate = startDate
        self.fireDate = fireDate
        self.minutesBefore = minutesBefore
        self.calendarColorHex = calendarColorHex
        self.accountId = accountId
        self.origin = origin
    }
}
