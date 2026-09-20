import XCTest
@testable import cal_reminder

private final class FakeTelemetryReporting: TelemetryReporting {
    var isConfigured: Bool
    var isEnabled: Bool

    init(isConfigured: Bool, isEnabled: Bool = true) {
        self.isConfigured = isConfigured
        self.isEnabled = isEnabled
    }

    func recordPlaneFlown(origin: TriggerOrigin) {}
    func recordActiveToday() {}
    func recordInstallationIfChanged() {}
}

final class TelemetryMenuBuilderTests: XCTestCase {
    func test_items_empty_whenNoTelemetry() {
        XCTAssertTrue(TelemetryMenuBuilder.items(for: nil, onToggle: {}).isEmpty)
    }

    func test_items_empty_whenNotConfigured() {
        let telemetry = FakeTelemetryReporting(isConfigured: false)

        XCTAssertTrue(TelemetryMenuBuilder.items(for: telemetry, onToggle: {}).isEmpty)
    }

    func test_items_configuredAndEnabled_showsOneCheckedItem() {
        let telemetry = FakeTelemetryReporting(isConfigured: true, isEnabled: true)

        let items = TelemetryMenuBuilder.items(for: telemetry, onToggle: {})

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, "Report anonymous usage")
        XCTAssertEqual(items[0].state, .on)
    }

    func test_items_configuredAndDisabled_showsOneUncheckedItem() {
        let telemetry = FakeTelemetryReporting(isConfigured: true, isEnabled: false)

        let items = TelemetryMenuBuilder.items(for: telemetry, onToggle: {})

        XCTAssertEqual(items[0].state, .off)
    }

    func test_items_toggling_callsThrough() {
        let telemetry = FakeTelemetryReporting(isConfigured: true)
        var toggled = false

        let items = TelemetryMenuBuilder.items(for: telemetry, onToggle: { toggled = true })
        _ = items[0].target?.perform(items[0].action!, with: items[0])

        XCTAssertTrue(toggled)
    }
}
