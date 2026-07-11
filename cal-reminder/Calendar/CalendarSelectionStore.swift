import Foundation

/// Persists which Calendars the user wants to be alerted on (RF-10). `nil` means the user
/// has never chosen — treated as "all Calendars" (the default). Wraps `UserDefaults` (the
/// persistence boundary, not a secret) so it can be faked in tests.
protocol CalendarSelectionStoring: AnyObject {
    var selectedCalendarIds: Set<String>? { get set }
}

extension CalendarSelectionStoring {
    /// Whether `id` is effectively selected: everything is selected until the user has
    /// chosen (`nil`), after which only `allIds` members present in the stored set count.
    func isSelected(_ id: String, within allIds: Set<String>) -> Bool {
        (selectedCalendarIds ?? allIds).contains(id)
    }

    /// Toggles `id`. The first toggle materializes the effective "all" set (so unchecking
    /// one Calendar keeps the others selected) before applying the change.
    func setSelected(_ id: String, _ selected: Bool, within allIds: Set<String>) {
        var current = selectedCalendarIds ?? allIds
        if selected {
            current.insert(id)
        } else {
            current.remove(id)
        }
        selectedCalendarIds = current
    }
}

final class UserDefaultsCalendarSelectionStore: CalendarSelectionStoring {
    private static let key = "selectedCalendarIds"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var selectedCalendarIds: Set<String>? {
        get {
            guard let stored = defaults.array(forKey: Self.key) as? [String] else { return nil }
            return Set(stored)
        }
        set {
            if let newValue {
                defaults.set(Array(newValue), forKey: Self.key)
            } else {
                defaults.removeObject(forKey: Self.key)
            }
        }
    }
}
