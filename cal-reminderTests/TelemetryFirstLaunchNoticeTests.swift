import XCTest
@testable import cal_reminder

private final class FakeTelemetrySettingsStore: TelemetrySettingsStoring {
    var enabled = true
    var noticeShown = false
    var lastActiveDay: Date?
    var lastSeenVersion: String?
    var pendingBatch = TelemetryPendingBatch()
}

final class TelemetryFirstLaunchNoticeTests: XCTestCase {
    func test_presentsOnce_thenNeverAgain() {
        // Arrange
        let store = FakeTelemetrySettingsStore()
        var presentCount = 0

        // Act
        TelemetryFirstLaunchNotice.presentIfNeeded(settingsStore: store, present: {
            presentCount += 1
            return .keepEnabled
        })
        TelemetryFirstLaunchNotice.presentIfNeeded(settingsStore: store, present: {
            presentCount += 1
            return .keepEnabled
        })

        // Assert
        XCTAssertEqual(presentCount, 1)
        XCTAssertTrue(store.noticeShown)
    }

    func test_keepEnabled_leavesTelemetryOn() {
        let store = FakeTelemetrySettingsStore()

        TelemetryFirstLaunchNotice.presentIfNeeded(settingsStore: store, present: { .keepEnabled })

        XCTAssertTrue(store.enabled)
    }

    func test_turnOff_disablesTelemetry() {
        let store = FakeTelemetrySettingsStore()

        TelemetryFirstLaunchNotice.presentIfNeeded(settingsStore: store, present: { .turnOff })

        XCTAssertFalse(store.enabled)
        XCTAssertTrue(store.noticeShown)
    }

    func test_alreadyShown_neverPresentsAgain() {
        let store = FakeTelemetrySettingsStore()
        store.noticeShown = true
        var presented = false

        TelemetryFirstLaunchNotice.presentIfNeeded(settingsStore: store, present: {
            presented = true
            return .keepEnabled
        })

        XCTAssertFalse(presented)
    }
}
