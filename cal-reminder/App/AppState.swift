import Foundation

/// Reflects a *verified* Google session, not just token presence (SPEC-010): `connecting`
/// covers the startup/reconnect verification window; `needsReauth` means the stored
/// refresh token was found dead (revoked/expired) and was cleared.
enum ConnectionStatus: Equatable {
    case disconnected
    case connecting
    case connected(email: String?)
    case needsReauth
}

/// Everything the MenuBar UI renders (RF-06): connection status, on/off, and the next
/// upcoming Trigger.
struct AppState: Equatable {
    var connectionStatus: ConnectionStatus = .disconnected
    var enabled = true
    var nextTrigger: Trigger?
    /// True while a manual Poll (RF-12) triggered from the empty state is in flight.
    var refreshing = false
    /// Every Calendar in the connected account, for the "Calendars" menu (RF-10).
    var calendars: [CalendarInfo] = []
}
