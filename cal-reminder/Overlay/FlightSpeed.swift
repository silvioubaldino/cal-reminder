import Foundation

/// The 3 Flight Speed presets the user can pick from the menu bar (RF-07).
enum FlightSpeed: String, CaseIterable {
    case slow
    case normal
    case fast

    var displayName: String {
        switch self {
        case .slow: return "Slow"
        case .normal: return "Normal"
        case .fast: return "Fast"
        }
    }

    /// Time the Airplane takes to cross the screen, in seconds.
    var flightDuration: CFTimeInterval {
        switch self {
        case .slow: return 9.0
        case .normal: return 6.0
        case .fast: return 3.5
        }
    }
}

/// Persists the user's chosen Flight Speed across restarts (RF-07). Wraps `UserDefaults`
/// (the persistence boundary) so it can be faked in tests.
protocol FlightSpeedStoring: AnyObject {
    var flightSpeed: FlightSpeed { get set }
}

final class UserDefaultsFlightSpeedStore: FlightSpeedStoring {
    private static let key = "flightSpeed"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var flightSpeed: FlightSpeed {
        get {
            defaults.string(forKey: Self.key).flatMap(FlightSpeed.init(rawValue:)) ?? .normal
        }
        set {
            defaults.set(newValue.rawValue, forKey: Self.key)
        }
    }
}
