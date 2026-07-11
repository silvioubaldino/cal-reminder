import Foundation

/// The computed moment to fire the animation: `Event start − Reminder minutes` (GLO: Trigger).
struct Trigger: Identifiable, Equatable, Sendable {
    /// Dedupe key: "<calendarId>#<eventId>#<minutes>" (RN-03).
    let id: String
    let eventTitle: String
    let startDate: Date
    let fireDate: Date
    let minutesBefore: Int
}
