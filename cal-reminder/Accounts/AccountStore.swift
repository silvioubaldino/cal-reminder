import Foundation

protocol AccountStoring: AnyObject {
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
