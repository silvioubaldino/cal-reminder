import XCTest
@testable import cal_reminder

private final class FakeTelemetrySettingsStore: TelemetrySettingsStoring {
    var enabled = true
    var noticeShown = false
    var lastActiveDay: Date?
    var lastSeenVersion: String?
    var pendingBatch = TelemetryPendingBatch()
}

private actor StubHTTPClient: HTTPClient {
    enum Mode {
        case accepted
        case rejected(status: Int)
        case networkFailure
    }

    private var mode: Mode
    private(set) var sentRequests: [URLRequest] = []

    init(mode: Mode = .accepted) {
        self.mode = mode
    }

    func setMode(_ mode: Mode) {
        self.mode = mode
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        sentRequests.append(request)
        switch mode {
        case .accepted:
            return (Data(), httpResponse(status: 202, url: request.url!))
        case .rejected(let status):
            return (Data(), httpResponse(status: status, url: request.url!))
        case .networkFailure:
            throw URLError(.notConnectedToInternet)
        }
    }
}

private func httpResponse(status: Int, url: URL) -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
}

private struct DecodedBatch: Decodable {
    let appVersion: String
    let macosMajor: String
    let events: [TelemetryEvent]
}

private func decode(_ request: URLRequest) throws -> DecodedBatch {
    try JSONDecoder().decode(DecodedBatch.self, from: request.httpBody!)
}

final class TelemetryClientTests: XCTestCase {
    private let config = TelemetryConfiguration(endpoint: URL(string: "https://telemetry.example.com")!, key: "shh")

    private func makeClient(
        httpClient: StubHTTPClient = StubHTTPClient(),
        settingsStore: FakeTelemetrySettingsStore = FakeTelemetrySettingsStore(),
        now: Date = Date(timeIntervalSince1970: 1_700_000_000),
        appVersion: String = "1.4.2"
    ) -> TelemetryClient {
        TelemetryClient(
            configuration: config,
            httpClient: httpClient,
            settingsStore: settingsStore,
            clock: { now },
            appVersion: { appVersion },
            macosMajor: { "15" }
        )
    }

    // MARK: TelemetryConfiguration.make

    func test_make_returnsConfiguration_forTwoRealValues() {
        let config = TelemetryConfiguration.make(endpoint: "https://telemetry.example.com", key: "abc123")

        XCTAssertEqual(config?.endpoint, URL(string: "https://telemetry.example.com"))
        XCTAssertEqual(config?.key, "abc123")
    }

    func test_make_nil_whenEndpointMissing() {
        XCTAssertNil(TelemetryConfiguration.make(endpoint: nil, key: "abc123"))
    }

    func test_make_nil_whenKeyMissing() {
        XCTAssertNil(TelemetryConfiguration.make(endpoint: "https://telemetry.example.com", key: nil))
    }

    func test_make_nil_whenEmpty() {
        XCTAssertNil(TelemetryConfiguration.make(endpoint: "", key: ""))
    }

    func test_make_nil_whenWhitespaceOnly() {
        XCTAssertNil(TelemetryConfiguration.make(endpoint: "   ", key: "\n\t"))
    }

    func test_make_nil_whenEndpointIsNotAValidURL() {
        XCTAssertNil(TelemetryConfiguration.make(endpoint: "not a url", key: "abc123"))
    }

    // MARK: recordPlaneFlown / flush

    func test_recordPlaneFlown_sendsWithoutWaitingForTheTimer() async {
        // Arrange
        let http = StubHTTPClient()
        let store = FakeTelemetrySettingsStore()
        let client = makeClient(httpClient: http, settingsStore: store)

        // Act
        client.recordPlaneFlown(origin: .eventReminder)
        await client.waitForPendingSends()

        // Assert
        let sent = await http.sentRequests
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(
            try! decode(sent[0]).events,
            [TelemetryEvent(name: "planes_flown", value: 1, kind: "event_reminder")]
        )
        XCTAssertTrue(store.pendingBatch.isEmpty)
    }

    func test_consecutiveFlights_areNeverReportedTwice() async {
        // Arrange
        let http = StubHTTPClient()
        let store = FakeTelemetrySettingsStore()
        let client = makeClient(httpClient: http, settingsStore: store)

        // Act
        client.recordPlaneFlown(origin: .eventReminder)
        client.recordPlaneFlown(origin: .eventReminder)
        client.recordPlaneFlown(origin: .eventReminder)
        await client.waitForPendingSends()

        // Assert
        let flown = await http.sentRequests
            .compactMap { try? decode($0) }
            .flatMap(\.events)
            .filter { $0.name == "planes_flown" }
            .reduce(0) { $0 + $1.value }
        XCTAssertEqual(flown, 3)
        XCTAssertTrue(store.pendingBatch.isEmpty)
    }

    func test_flightsOfDifferentOrigins_areReportedAsSeparateKindedEvents() async {
        // Arrange
        let http = StubHTTPClient()
        let store = FakeTelemetrySettingsStore()
        let client = makeClient(httpClient: http, settingsStore: store)

        // Act
        client.recordPlaneFlown(origin: .eventReminder)
        client.recordPlaneFlown(origin: .extraReminder)
        client.recordPlaneFlown(origin: .testAnimation)
        await client.waitForPendingSends()

        // Assert
        let events = await http.sentRequests.compactMap { try? decode($0) }.flatMap(\.events)
        let planesFlownByKind = Dictionary(uniqueKeysWithValues: events
            .filter { $0.name == "planes_flown" }
            .compactMap { event -> (String, Int)? in
                guard let kind = event.kind else { return nil }
                return (kind, event.value)
            })
        XCTAssertEqual(planesFlownByKind, ["event_reminder": 1, "extra_reminder": 1, "test_animation": 1])
        XCTAssertTrue(store.pendingBatch.isEmpty)
    }

    func test_flush_withNothingPending_sendsNothing() async {
        // Arrange
        let http = StubHTTPClient()
        let client = makeClient(httpClient: http)

        // Act
        await client.flush()

        // Assert
        let sent = await http.sentRequests
        XCTAssertTrue(sent.isEmpty)
    }

    func test_flush_sendsTheKeyHeaderAndPath() async {
        // Arrange
        let http = StubHTTPClient()
        let client = makeClient(httpClient: http)

        // Act
        client.recordActiveToday()
        await client.flush()

        // Assert
        let sent = await http.sentRequests
        XCTAssertEqual(sent[0].url, URL(string: "https://telemetry.example.com/v1/events"))
        XCTAssertEqual(sent[0].httpMethod, "POST")
        XCTAssertEqual(sent[0].value(forHTTPHeaderField: "X-Telemetry-Key"), "shh")
    }

    // MARK: recordActiveToday

    func test_recordActiveToday_queuesOnce_secondCallSameDayIsANoOp() async {
        // Arrange
        let http = StubHTTPClient()
        let store = FakeTelemetrySettingsStore()
        let client = makeClient(httpClient: http, settingsStore: store)

        // Act
        client.recordActiveToday()
        client.recordActiveToday()
        await client.flush()

        // Assert
        let sent = await http.sentRequests
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(try! decode(sent[0]).events, [TelemetryEvent(name: "daily_active", value: 1)])
    }

    func test_recordActiveToday_doesNotRequeue_afterAlreadyFlushedThatDay() async {
        // Arrange
        let http = StubHTTPClient()
        let store = FakeTelemetrySettingsStore()
        let client = makeClient(httpClient: http, settingsStore: store)
        client.recordActiveToday()
        await client.flush()

        // Act
        client.recordActiveToday()
        await client.flush()

        // Assert
        let sent = await http.sentRequests
        XCTAssertEqual(sent.count, 1)
    }

    func test_recordActiveToday_queuesAgain_onANewDay() async {
        // Arrange
        let http = StubHTTPClient()
        let store = FakeTelemetrySettingsStore()
        let day1 = Date(timeIntervalSince1970: 1_700_000_000)
        let client1 = TelemetryClient(configuration: config, httpClient: http, settingsStore: store, clock: { day1 }, appVersion: { "1.4.2" }, macosMajor: { "15" })
        client1.recordActiveToday()
        await client1.flush()

        // Act
        let day2 = day1.addingTimeInterval(36 * 60 * 60)
        let client2 = TelemetryClient(configuration: config, httpClient: http, settingsStore: store, clock: { day2 }, appVersion: { "1.4.2" }, macosMajor: { "15" })
        client2.recordActiveToday()
        await client2.flush()

        // Assert
        let sent = await http.sentRequests
        XCTAssertEqual(sent.count, 2)
    }

    func test_recordActiveToday_survivesRestart_sameDayIsStillANoOp() async {
        // Arrange
        let http = StubHTTPClient()
        let store = FakeTelemetrySettingsStore()
        let client1 = makeClient(httpClient: http, settingsStore: store)
        client1.recordActiveToday()
        await client1.flush()

        // Act
        let client2 = makeClient(httpClient: http, settingsStore: store)
        client2.recordActiveToday()

        // Assert
        XCTAssertTrue(store.pendingBatch.isEmpty)
    }

    func test_aFlightCarriesThePendingDailyActive_inTheSameBatch() async {
        // Arrange
        let http = StubHTTPClient()
        let client = makeClient(httpClient: http)
        client.recordActiveToday()

        // Act
        client.recordPlaneFlown(origin: .eventReminder)
        await client.waitForPendingSends()

        // Assert
        let sent = await http.sentRequests
        XCTAssertEqual(sent.count, 1)
        let events = Set(try! decode(sent[0]).events.map(\.name))
        XCTAssertEqual(events, ["planes_flown", "daily_active"])
    }

    // MARK: recordInstallationIfChanged

    func test_recordInstallationIfChanged_firstInstall_whenNoVersionStored() async {
        // Arrange
        let http = StubHTTPClient()
        let store = FakeTelemetrySettingsStore()
        XCTAssertNil(store.lastSeenVersion)
        let client = makeClient(httpClient: http, settingsStore: store, appVersion: "1.4.2")

        // Act
        client.recordInstallationIfChanged()
        await client.flush()

        // Assert
        let batch = try! decode(await http.sentRequests[0])
        XCTAssertEqual(batch.events, [TelemetryEvent(name: "installation", value: 1, kind: "first_install")])
        XCTAssertEqual(store.lastSeenVersion, "1.4.2")
    }

    func test_recordInstallationIfChanged_update_whenStoredVersionDiffers() async {
        // Arrange
        let http = StubHTTPClient()
        let store = FakeTelemetrySettingsStore()
        store.lastSeenVersion = "1.4.1"
        let client = makeClient(httpClient: http, settingsStore: store, appVersion: "1.4.2")

        // Act
        client.recordInstallationIfChanged()
        await client.flush()

        // Assert
        let batch = try! decode(await http.sentRequests[0])
        XCTAssertEqual(batch.appVersion, "1.4.2")
        XCTAssertEqual(batch.events, [TelemetryEvent(name: "installation", value: 1, kind: "update")])
    }

    func test_recordInstallationIfChanged_noOp_whenVersionUnchanged() async {
        // Arrange
        let http = StubHTTPClient()
        let store = FakeTelemetrySettingsStore()
        store.lastSeenVersion = "1.4.2"
        let client = makeClient(httpClient: http, settingsStore: store, appVersion: "1.4.2")

        // Act
        client.recordInstallationIfChanged()
        await client.flush()

        // Assert
        let sent = await http.sentRequests
        XCTAssertTrue(sent.isEmpty)
    }

    // MARK: failure and acceptance

    func test_failedSend_leavesThePendingBatchUnchanged_laterEventsAreAddedToIt() async {
        // Arrange
        let http = StubHTTPClient(mode: .networkFailure)
        let store = FakeTelemetrySettingsStore()
        let client = makeClient(httpClient: http, settingsStore: store)
        client.recordPlaneFlown(origin: .eventReminder)
        client.recordPlaneFlown(origin: .eventReminder)
        await client.waitForPendingSends()
        XCTAssertEqual(store.pendingBatch.planesFlown["event_reminder"], 2)

        // Act
        await http.setMode(.accepted)
        client.recordPlaneFlown(origin: .eventReminder)
        await client.waitForPendingSends()

        // Assert
        let sent = await http.sentRequests
        XCTAssertEqual(
            try! decode(sent[sent.count - 1]).events,
            [TelemetryEvent(name: "planes_flown", value: 3, kind: "event_reminder")]
        )
        XCTAssertTrue(store.pendingBatch.isEmpty)
    }

    func test_pendingBatch_clearedOnlyOnAcceptance() async {
        // Arrange
        let http = StubHTTPClient(mode: .rejected(status: 500))
        let store = FakeTelemetrySettingsStore()
        let client = makeClient(httpClient: http, settingsStore: store)

        // Act
        client.recordPlaneFlown(origin: .eventReminder)
        await client.waitForPendingSends()

        // Assert
        XCTAssertFalse(store.pendingBatch.isEmpty)
    }

    // MARK: the switch

    func test_disablingTelemetry_discardsThePendingBatch() async {
        // Arrange
        let store = FakeTelemetrySettingsStore()
        let client = makeClient(httpClient: StubHTTPClient(mode: .networkFailure), settingsStore: store)
        client.recordPlaneFlown(origin: .eventReminder)
        await client.waitForPendingSends()
        XCTAssertFalse(store.pendingBatch.isEmpty)

        // Act
        client.isEnabled = false

        // Assert
        XCTAssertTrue(store.pendingBatch.isEmpty)
    }

    func test_disabledTelemetry_recordMethodsAreNoOps() async {
        // Arrange
        let http = StubHTTPClient()
        let store = FakeTelemetrySettingsStore()
        let client = makeClient(httpClient: http, settingsStore: store)
        client.isEnabled = false

        // Act
        client.recordPlaneFlown(origin: .eventReminder)
        client.recordActiveToday()
        client.recordInstallationIfChanged()
        await client.flush()

        // Assert
        XCTAssertTrue(store.pendingBatch.isEmpty)
        let sent = await http.sentRequests
        XCTAssertTrue(sent.isEmpty)
    }

    func test_isEnabled_persistsThroughTheSettingsStore() {
        let store = FakeTelemetrySettingsStore()
        let client = makeClient(settingsStore: store)

        client.isEnabled = false

        XCTAssertFalse(store.enabled)
        XCTAssertFalse(client.isEnabled)
    }
}
