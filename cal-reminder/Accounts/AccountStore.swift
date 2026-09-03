import Foundation

/// Persists the ordered list of connected Accounts (RF-14). Not a secret — the Keychain
/// holds each Account's token; this is just identity + display metadata, so `UserDefaults`
/// is the right boundary (same pattern as `CalendarSelectionStore`/`FlightSpeedStore`).
protocol AccountStoring: AnyObject {
    /// Ordered by connection order (first connected, first shown — AYD-007).
    var accounts: [Account] { get set }
}

final class UserDefaultsAccountStore: AccountStoring {
    private static let key = "connectedAccounts"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var accounts: [Account] {
        get {
            guard let data = defaults.data(forKey: Self.key) else { return [] }
            return (try? JSONDecoder().decode([Account].self, from: data)) ?? []
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            defaults.set(data, forKey: Self.key)
        }
    }
}
