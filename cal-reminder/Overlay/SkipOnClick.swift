import Foundation

/// Persists whether a click anywhere skips a playing flight (RF-09) across restarts.
/// Wraps `UserDefaults` (the persistence boundary) so it can be faked in tests.
protocol SkipOnClickStoring: AnyObject {
    var skipOnClick: Bool { get set }
}

final class UserDefaultsSkipOnClickStore: SkipOnClickStoring {
    private static let key = "skipOnClick"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var skipOnClick: Bool {
        get {
            defaults.object(forKey: Self.key) as? Bool ?? true
        }
        set {
            defaults.set(newValue, forKey: Self.key)
        }
    }
}
