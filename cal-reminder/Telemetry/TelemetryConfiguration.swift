import Foundation

struct TelemetryConfiguration {
    let endpoint: URL
    let key: String

    static func make(endpoint: String?, key: String?) -> TelemetryConfiguration? {
        guard
            let endpointString = endpoint?.trimmingCharacters(in: .whitespacesAndNewlines), !endpointString.isEmpty,
            let url = URL(string: endpointString),
            let scheme = url.scheme, scheme == "http" || scheme == "https",
            url.host != nil,
            let key = key?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty
        else {
            return nil
        }
        return TelemetryConfiguration(endpoint: url, key: key)
    }
}

struct TelemetryEvent: Codable, Equatable {
    let name: String
    let value: Int
    var kind: String?
}

struct TelemetryBatchRequest: Encodable {
    let appVersion: String
    let macosMajor: String
    let events: [TelemetryEvent]
}

protocol TelemetryReporting: AnyObject {
    var isConfigured: Bool { get }
    var isEnabled: Bool { get set }
    func recordPlaneFlown(origin: TriggerOrigin)
    func recordActiveToday()
    func recordInstallationIfChanged()
}
