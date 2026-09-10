import Foundation

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
    /// The Account (GLO) this Trigger's Event came from — lets the Scheduler reconcile and
    /// cancel Triggers scoped to one Account without a Poll failure elsewhere disarming it
    /// (RF-14, RNF-04, AYD-011).
    let accountId: String

    init(
        id: String,
        eventTitle: String,
        startDate: Date,
        fireDate: Date,
        minutesBefore: Int,
        calendarColorHex: String? = nil,
        accountId: String
    ) {
        self.id = id
        self.eventTitle = eventTitle
        self.startDate = startDate
        self.fireDate = fireDate
        self.minutesBefore = minutesBefore
        self.calendarColorHex = calendarColorHex
        self.accountId = accountId
    }
}
