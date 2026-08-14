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

extension NSColor {
    /// Parses a Calendar Color as returned by the Google Calendar API — `"#0088aa"`, or the
    /// same without the leading `#` (RF-13). Returns nil for anything else, so an
    /// unexpected value falls back to the Banner color preset instead of painting garbage.
    convenience init?(bannerHex hex: String) {
        var digits = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if digits.hasPrefix("#") {
            digits.removeFirst()
        }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }

        self.init(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    /// The Banner text color that stays readable on top of `self` (RF-13): white on a dark
    /// Banner, near-black on a light one. Derived from perceived luminance rather than from
    /// Google's `foregroundColor`, which is tuned for its own web UI, not for this Banner.
    var readableBannerTextColor: NSColor {
        guard let rgb = usingColorSpace(.sRGB) else { return .white }
        let luminance = 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
        return luminance > 0.6 ? NSColor(srgbRed: 0.1, green: 0.1, blue: 0.1, alpha: 1) : .white
    }
}

/// Persists whether each Banner is painted with its Event's Calendar Color instead of the
/// color preset (RF-13). Defaults to **on**: that's the behavior the feature exists for,
/// and the menu turns it off in one click, falling back to the preset (RF-08).
protocol MatchCalendarColorStoring: AnyObject {
    var matchCalendarColor: Bool { get set }
}

final class UserDefaultsMatchCalendarColorStore: MatchCalendarColorStoring {
    private static let key = "matchCalendarColor"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var matchCalendarColor: Bool {
        get {
            defaults.object(forKey: Self.key) as? Bool ?? true
        }
        set {
            defaults.set(newValue, forKey: Self.key)
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
