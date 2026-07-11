import AppKit

/// The Banner color presets the user can pick from the menu bar (RF-07).
enum BannerColor: String, CaseIterable {
    case pink
    case blue
    case green
    case orange
    case purple

    var displayName: String {
        switch self {
        case .pink: return "Pink"
        case .blue: return "Blue"
        case .green: return "Green"
        case .orange: return "Orange"
        case .purple: return "Purple"
        }
    }

    var color: NSColor {
        switch self {
        case .pink: return .systemPink
        case .blue: return .systemBlue
        case .green: return .systemGreen
        case .orange: return .systemOrange
        case .purple: return .systemPurple
        }
    }
}

/// Persists the user's chosen Banner color across restarts (RF-07). Wraps `UserDefaults`
/// (the persistence boundary) so it can be faked in tests.
protocol BannerColorStoring: AnyObject {
    var bannerColor: BannerColor { get set }
}

final class UserDefaultsBannerColorStore: BannerColorStoring {
    private static let key = "bannerColor"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var bannerColor: BannerColor {
        get {
            defaults.string(forKey: Self.key).flatMap(BannerColor.init(rawValue:)) ?? .pink
        }
        set {
            defaults.set(newValue.rawValue, forKey: Self.key)
        }
    }
}
