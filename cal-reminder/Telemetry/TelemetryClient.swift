import Foundation

final class TelemetryClient: TelemetryReporting {
    let isConfigured = true

    private let configuration: TelemetryConfiguration
    private let httpClient: HTTPClient
    private let settingsStore: TelemetrySettingsStoring
    private let calendar: Calendar
    private let clock: () -> Date
    private let appVersion: () -> String
    private let macosMajor: () -> String
    private let sendInterval: TimeInterval
    private var timer: Timer?

    init(
        configuration: TelemetryConfiguration,
        httpClient: HTTPClient = URLSessionHTTPClient(),
        settingsStore: TelemetrySettingsStoring = UserDefaultsTelemetrySettingsStore(),
        calendar: Calendar = .current,
        clock: @escaping () -> Date = Date.init,
        sendInterval: TimeInterval = 3600,
        appVersion: @escaping () -> String = {
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        },
        macosMajor: @escaping () -> String = {
            String(ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
        }
    ) {
        self.configuration = configuration
        self.httpClient = httpClient
        self.settingsStore = settingsStore
        self.calendar = calendar
        self.clock = clock
        self.sendInterval = sendInterval
        self.appVersion = appVersion
        self.macosMajor = macosMajor
    }

    var isEnabled: Bool {
        get { settingsStore.enabled }
        set {
            settingsStore.enabled = newValue
            if !newValue {
                settingsStore.pendingBatch = TelemetryPendingBatch()
            }
        }
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: sendInterval, repeats: true) { [weak self] _ in
            Task { await self?.tick() }
        }
    }

    func recordPlaneFlown() {
        guard isEnabled else { return }
        var batch = settingsStore.pendingBatch
        batch.planesFlown += 1
        settingsStore.pendingBatch = batch
    }

    func recordActiveToday() {
        guard isEnabled else { return }
        let today = calendar.startOfDay(for: clock())
        if let lastActiveDay = settingsStore.lastActiveDay, calendar.isDate(lastActiveDay, inSameDayAs: today) {
            return
        }
        settingsStore.lastActiveDay = today
        var batch = settingsStore.pendingBatch
        batch.dailyActiveQueued = true
        settingsStore.pendingBatch = batch
    }

    func recordInstallationIfChanged() {
        guard isEnabled else { return }
        let running = appVersion()
        let lastSeen = settingsStore.lastSeenVersion
        guard lastSeen != running else { return }
        settingsStore.lastSeenVersion = running
        var batch = settingsStore.pendingBatch
        batch.installationKind = lastSeen == nil ? "first_install" : "update"
        settingsStore.pendingBatch = batch
    }

    private func tick() async {
        recordActiveToday()
        await flush()
    }

    func flush() async {
        guard isEnabled else { return }
        let batch = settingsStore.pendingBatch
        guard !batch.isEmpty else { return }

        let body = TelemetryBatchRequest(appVersion: appVersion(), macosMajor: macosMajor(), events: batch.events)
        guard let data = try? JSONEncoder().encode(body) else { return }

        var request = URLRequest(url: configuration.endpoint.appendingPathComponent("v1/events"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(configuration.key, forHTTPHeaderField: "X-Telemetry-Key")
        request.httpBody = data
        request.timeoutInterval = 10

        guard let (_, response) = try? await httpClient.send(request), response.statusCode == 202 else {
            return
        }
        settingsStore.pendingBatch = TelemetryPendingBatch()
    }
}
