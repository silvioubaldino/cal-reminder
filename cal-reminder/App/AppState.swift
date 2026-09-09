import Foundation

enum ConnectionStatus: Equatable {
    case disconnected
    case connecting
    case connected
    case needsReauth
}

struct AccountState: Identifiable, Equatable {
    let id: String
    let label: String
    var connectionStatus: ConnectionStatus
    var calendars: [CalendarInfo] = []
}

struct AppState: Equatable {
    var accounts: [AccountState] = []
    var enabled = true
    var nextTrigger: Trigger?
    var refreshing = false
    var oauthConfigured = true

    var statusTitle: String {
        if !oauthConfigured { return "Setup needed — no Google client" }
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
