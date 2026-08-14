import Foundation

/// The computed moment to fire the animation: `Event start − Reminder minutes` (GLO: Trigger).
struct Trigger: Identifiable, Equatable, Sendable {
    /// Dedupe key: "<calendarId>#<eventId>#<minutes>" (RN-03).
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

    init(
        id: String,
        eventTitle: String,
        startDate: Date,
        fireDate: Date,
        minutesBefore: Int,
        calendarColorHex: String? = nil
    ) {
        self.id = id
        self.eventTitle = eventTitle
        self.startDate = startDate
        self.fireDate = fireDate
        self.minutesBefore = minutesBefore
        self.calendarColorHex = calendarColorHex
    }
}
