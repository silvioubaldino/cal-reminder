import Foundation

/// Which Reminders the user wants to fly (RF-15): the Event's own ones, plus any number of
/// **Extra Reminders** (GLO) the app adds to every Event. A pure value — the resolver (RN-07)
/// and the menu both read the presets, labels and summary from here.
struct ReminderSettings: Equatable {
    /// Fixed Extra Reminder presets, in minutes before the Event's start. `0` = at start time.
    static let presetMinutes = [0, 1, 5, 10, 15]

    /// Defaults reproduce the behavior before RF-15 existed: the Event's own Reminders, nothing added.
    static let `default` = ReminderSettings()

    /// Whether the Event's own Reminders (RN-04, with RN-06's fallback) are used at all.
    var inheritEventReminders = true
    /// The checked Extra Reminders, in minutes before the Event's start.
    var extraMinutes: Set<Int> = []

    /// No Reminder of any kind is selected — no Event would ever be announced.
    var isSilent: Bool {
        !inheritEventReminders && extraMinutes.isEmpty
    }

    /// Row label of one preset: "At start time" / "1 minute before" / "10 minutes before".
    static func label(forMinutes minutes: Int) -> String {
        switch minutes {
        case 0: return "At start time"
        case 1: return "1 minute before"
        default: return "\(minutes) minutes before"
        }
    }

    /// Compact statement of the current selection — "calendar + 1, 5 min", "10 min, at start",
    /// "calendar", "none" — so the menu can state it without being opened (AYD-008).
    var summary: String {
        var parts: [String] = []
        if inheritEventReminders {
            parts.append("calendar")
        }

        let sorted = extraMinutes.sorted()
        let numeric = sorted.filter { $0 > 0 }
        var extras: [String] = []
        if !numeric.isEmpty {
            let list = numeric.map { minutes in "\(minutes)" }.joined(separator: ", ")
            extras.append("\(list) min")
        }
        if sorted.contains(0) {
            extras.append("at start")
        }

        let joinedExtras = extras.joined(separator: ", ")
        if !joinedExtras.isEmpty {
            parts.append(joinedExtras)
        }

        return parts.isEmpty ? "none" : parts.joined(separator: " + ")
    }

    /// Title of the menu item that owns the submenu, carrying the selection inline.
    var menuTitle: String {
        "Reminders (\(summary))"
    }
}

/// Persists the Reminder selection (RF-15) across restarts, app-wide.
/// Wraps `UserDefaults` (the persistence boundary) so it can be faked in tests.
protocol ReminderSettingsStoring: AnyObject {
    var settings: ReminderSettings { get set }
}

final class UserDefaultsReminderSettingsStore: ReminderSettingsStoring {
    private static let inheritKey = "inheritEventReminders"
    private static let extraMinutesKey = "extraReminderMinutes"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var settings: ReminderSettings {
        get {
            ReminderSettings(
                inheritEventReminders: defaults.object(forKey: Self.inheritKey) as? Bool ?? true,
                extraMinutes: Set(defaults.array(forKey: Self.extraMinutesKey) as? [Int] ?? [])
            )
        }
        set {
            defaults.set(newValue.inheritEventReminders, forKey: Self.inheritKey)
            defaults.set(newValue.extraMinutes.sorted(), forKey: Self.extraMinutesKey)
        }
    }
}
