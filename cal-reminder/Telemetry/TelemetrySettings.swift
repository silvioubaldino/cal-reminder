import Foundation

struct TelemetryPendingBatch: Codable, Equatable {
    var planesFlown: Int = 0
    var dailyActiveQueued: Bool = false
    var installationKind: String?

    var isEmpty: Bool {
        planesFlown == 0 && !dailyActiveQueued && installationKind == nil
    }

    var events: [TelemetryEvent] {
        var events: [TelemetryEvent] = []
        if planesFlown > 0 {
            events.append(TelemetryEvent(name: "planes_flown", value: planesFlown))
        }
        if dailyActiveQueued {
            events.append(TelemetryEvent(name: "daily_active", value: 1))
        }
        if let installationKind {
            events.append(TelemetryEvent(name: "installation", value: 1, kind: installationKind))
        }
        return events
    }
}

protocol TelemetrySettingsStoring: AnyObject {
    var enabled: Bool { get set }
    var noticeShown: Bool { get set }
    var lastActiveDay: Date? { get set }
    var lastSeenVersion: String? { get set }
    var pendingBatch: TelemetryPendingBatch { get set }
}

final class UserDefaultsTelemetrySettingsStore: TelemetrySettingsStoring {
    private enum Keys {
        static let enabled = "telemetryEnabled"
        static let noticeShown = "telemetryNoticeShown"
        static let lastActiveDay = "telemetryLastActiveDay"
        static let lastSeenVersion = "telemetryLastSeenVersion"
        static let pendingBatch = "telemetryPendingBatch"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var enabled: Bool {
        get { defaults.object(forKey: Keys.enabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.enabled) }
    }

    var noticeShown: Bool {
        get { defaults.bool(forKey: Keys.noticeShown) }
        set { defaults.set(newValue, forKey: Keys.noticeShown) }
    }

    var lastActiveDay: Date? {
        get { defaults.object(forKey: Keys.lastActiveDay) as? Date }
        set { defaults.set(newValue, forKey: Keys.lastActiveDay) }
    }

    var lastSeenVersion: String? {
        get { defaults.string(forKey: Keys.lastSeenVersion) }
        set { defaults.set(newValue, forKey: Keys.lastSeenVersion) }
    }

    var pendingBatch: TelemetryPendingBatch {
        get {
            guard
                let data = defaults.data(forKey: Keys.pendingBatch),
                let batch = try? JSONDecoder().decode(TelemetryPendingBatch.self, from: data)
            else {
                return TelemetryPendingBatch()
            }
            return batch
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: Keys.pendingBatch)
        }
    }
}
