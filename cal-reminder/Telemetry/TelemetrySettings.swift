import Foundation

/// What has accumulated locally since the last accepted batch, and what still needs deciding.
/// `planesFlown` is a delta (cleared on acceptance); `dailyActiveQueued` and `installationKind`
/// are one-shot decisions the client makes at most once per day / once per version, independent
/// of whether the send that carries them has succeeded yet (SPEC-023).
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
    /// The menu bar switch (RF-17). Defaults to **on** — a pure opt-in under-reports too
    /// badly to be useful (AYD-013).
    var enabled: Bool { get set }
    /// Whether the first-launch notice has been shown; nothing is sent before it has (RF-17).
    var noticeShown: Bool { get set }
    /// The local calendar day `daily_active` was last decided for — not necessarily sent yet.
    var lastActiveDay: Date? { get set }
    /// The app version last seen running, to detect a first install or an update.
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
