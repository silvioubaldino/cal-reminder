import Foundation

/// Build-time configuration for the Project Service (AYD-013). Mirrors
/// `UpdateConfiguration.make` exactly: `nil` when either value is missing, which is what keeps
/// a Source Build silent (RNF-13) — with no configuration, no `TelemetryClient` is ever built.
struct TelemetryConfiguration {
    let endpoint: URL
    let key: String

    static func make(endpoint: String?, key: String?) -> TelemetryConfiguration? {
        guard
            let endpointString = endpoint?.trimmingCharacters(in: .whitespacesAndNewlines), !endpointString.isEmpty,
            let url = URL(string: endpointString),
            let key = key?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty
        else {
            return nil
        }
        return TelemetryConfiguration(endpoint: url, key: key)
    }
}

/// A single counter event in a batch, per AYD-013's `/v1/events` contract. `kind` is only
/// present on an `installation` event (`first_install` | `update`).
struct TelemetryEvent: Codable, Equatable {
    let name: String
    let value: Int
    var kind: String? = nil
}

/// The `/v1/events` request body.
struct TelemetryBatchRequest: Encodable {
    let appVersion: String
    let macosMajor: String
    let events: [TelemetryEvent]
}

protocol TelemetryReporting: AnyObject {
    var isConfigured: Bool { get }
    var isEnabled: Bool { get set }
    func recordPlaneFlown()
    func recordActiveToday()
    func recordInstallationIfChanged()
}
