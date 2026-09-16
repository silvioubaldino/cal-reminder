import XCTest
@testable import cal_reminder

final class TelemetrySettingsStoreTests: XCTestCase {
    private func makeStore() -> UserDefaultsTelemetrySettingsStore {
        let suiteName = "TelemetrySettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return UserDefaultsTelemetrySettingsStore(defaults: defaults)
    }

    func test_enabled_defaultsToTrue() {
        // Telemetry is on by default (AYD-013) — a pure opt-in under-reports too badly.
        XCTAssertTrue(makeStore().enabled)
    }

    func test_noticeShown_defaultsToFalse() {
        XCTAssertFalse(makeStore().noticeShown)
    }

    func test_lastActiveDay_defaultsToNil() {
        XCTAssertNil(makeStore().lastActiveDay)
    }

    func test_lastSeenVersion_defaultsToNil() {
        XCTAssertNil(makeStore().lastSeenVersion)
    }

    func test_pendingBatch_defaultsToEmpty() {
        XCTAssertTrue(makeStore().pendingBatch.isEmpty)
    }

    func test_roundTripsEveryField() {
        // Arrange
        let store = makeStore()
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        var batch = TelemetryPendingBatch()
        batch.planesFlown = 5
        batch.dailyActiveQueued = true
        batch.installationKind = "update"

        // Act
        store.enabled = false
        store.noticeShown = true
        store.lastActiveDay = day
        store.lastSeenVersion = "1.4.2"
        store.pendingBatch = batch

        // Assert
        XCTAssertFalse(store.enabled)
        XCTAssertTrue(store.noticeShown)
        XCTAssertEqual(store.lastActiveDay, day)
        XCTAssertEqual(store.lastSeenVersion, "1.4.2")
        XCTAssertEqual(store.pendingBatch, batch)
    }

    func test_persistsAcrossStoreInstancesSharingTheSameDefaults() {
        // Arrange
        let suiteName = "TelemetrySettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = UserDefaultsTelemetrySettingsStore(defaults: defaults)
        var batch = TelemetryPendingBatch()
        batch.planesFlown = 2

        // Act
        store.enabled = false
        store.lastSeenVersion = "1.4.2"
        store.pendingBatch = batch
        let relaunchedStore = UserDefaultsTelemetrySettingsStore(defaults: defaults)

        // Assert
        XCTAssertFalse(relaunchedStore.enabled)
        XCTAssertEqual(relaunchedStore.lastSeenVersion, "1.4.2")
        XCTAssertEqual(relaunchedStore.pendingBatch, batch)
    }
}
