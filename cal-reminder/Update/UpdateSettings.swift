import Foundation

protocol UpdateSettingsStoring: AnyObject {
    var automaticallyChecks: Bool { get set }
}

final class UserDefaultsUpdateSettingsStore: UpdateSettingsStoring {
    private static let key = "updateAutomaticallyChecks"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var automaticallyChecks: Bool {
        get {
            defaults.object(forKey: Self.key) as? Bool ?? false
        }
        set {
            defaults.set(newValue, forKey: Self.key)
        }
    }
}
