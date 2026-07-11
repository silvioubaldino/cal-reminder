import Foundation

/// Everything the MenuBar UI renders (RF-06): connection status, on/off, and the next
/// upcoming Trigger.
struct AppState: Equatable {
    var connected = false
    var enabled = true
    var nextTrigger: Trigger?
    /// The connected Google account's email, shown as "Connected as <email>" (RF-06).
    var userEmail: String?
    /// Every Calendar in the connected account, for the "Calendars" menu (RF-10).
    var calendars: [CalendarInfo] = []
}
