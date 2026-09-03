import Foundation

protocol CalendarSelectionStoring: AnyObject {
    var selectedCalendarIds: Set<String>? { get set }
}

extension CalendarSelectionStoring {
    func isSelected(_ id: String, within allIds: Set<String>) -> Bool {
        (selectedCalendarIds ?? allIds).contains(id)
    }

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
    static let legacyKey = "selectedCalendarIds"

    private let key: String
    private let defaults: UserDefaults

    init(accountId: String, defaults: UserDefaults = .standard) {
        self.key = "\(Self.legacyKey).\(accountId)"
        self.defaults = defaults
    }

    var selectedCalendarIds: Set<String>? {
        get {
            guard let stored = defaults.array(forKey: key) as? [String] else { return nil }
            return Set(stored)
        }
        set {
            if let newValue {
                defaults.set(Array(newValue), forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }
}
