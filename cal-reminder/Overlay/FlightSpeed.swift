import Foundation
import CoreGraphics

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

    /// A typical laptop screen width (points), used only to calibrate `pointsPerSecond`
    /// so each preset's speed feels the same as it did when defined.
    private static let referenceScreenWidth: CGFloat = 1440

    /// How long the flight takes to cross a screen of `referenceScreenWidth`, in seconds.
    private var referenceCrossingDuration: CFTimeInterval {
        switch self {
        case .slow: return 15.0
        case .normal: return 12.0
        case .fast: return 9.0
        }
    }

    /// Points the Airplane travels per second. Constant per preset regardless of
    /// monitor size, so an ultrawide and a small screen feel equally fast (RF-07).
    var pointsPerSecond: CGFloat {
        (Self.referenceScreenWidth + AirplaneBannerView.containerWidth) / Self.cgFloat(referenceCrossingDuration)
    }

    /// Time the Airplane takes to cross a screen of `screenWidth` points at this
    /// preset's speed. `containerWidth` is the actual width of the Airplane + rope +
    /// Banner group, which grows when a long title widens the Banner — passing it keeps
    /// the flight at the same points per second instead of looking faster (RF-07).
    func flightDuration(
        forScreenWidth screenWidth: CGFloat,
        containerWidth: CGFloat = AirplaneBannerView.containerWidth
    ) -> CFTimeInterval {
        Double((screenWidth + containerWidth) / pointsPerSecond)
    }

    private static func cgFloat(_ value: CFTimeInterval) -> CGFloat { CGFloat(value) }
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
