import Foundation

/// Reflects a *verified* Google session, not just token presence (SPEC-010): `connecting`
/// covers the startup/reconnect verification window; `needsReauth` means the stored
/// refresh token was found dead (revoked/expired) and was cleared. The connected Account's
/// email lives on `AccountState.label` (RF-14), not here — one `ConnectionStatus` exists
/// per Account.
enum ConnectionStatus: Equatable {
    case disconnected
    case connecting
    case connected
    case needsReauth
}

/// One connected Account's state, as rendered by the menu bar (RF-14).
struct AccountState: Identifiable, Equatable {
    let id: String
    /// Display label — the Account's email (RF-06).
    let label: String
    var connectionStatus: ConnectionStatus
    /// Every Calendar in this Account, for its "Calendars" submenu (RF-10).
    var calendars: [CalendarInfo] = []
}

/// Everything the MenuBar UI renders (RF-06): every connected Account, on/off, and the next
/// upcoming Trigger.
struct AppState: Equatable {
    var accounts: [AccountState] = []
    var enabled = true
    var nextTrigger: Trigger?
    /// True while a manual Poll (RF-12) triggered from the empty state is in flight.
    var refreshing = false

    /// The menu bar's status line (RF-06/RF-14): summarizes every connected Account's state
    /// into a single line, whether there are none, one, or several.
    var statusTitle: String {
        if accounts.isEmpty { return "Not connected" }

        let needingReauth = accounts.filter { $0.connectionStatus == .needsReauth }.count
        if accounts.allSatisfy({ $0.connectionStatus == .connecting }) { return "Connecting…" }

        if accounts.count == 1 {
            let account = accounts[0]
            switch account.connectionStatus {
            case .connected: return "Connected as \(account.label)"
            case .connecting: return "Connecting…"
            case .needsReauth: return "Reconnect needed"
            case .disconnected: return "Not connected"
            }
        }

        if needingReauth > 0 {
            return "\(accounts.count) accounts · \(needingReauth) need\(needingReauth == 1 ? "s" : "") reconnecting"
        }
        return "Connected · \(accounts.count) accounts"
    }
}
