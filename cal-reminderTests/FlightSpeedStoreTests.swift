import XCTest
@testable import cal_reminder

final class FlightSpeedStoreTests: XCTestCase {
    private func makeStore() -> UserDefaultsFlightSpeedStore {
        let suiteName = "FlightSpeedStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return UserDefaultsFlightSpeedStore(defaults: defaults)
    }

    func test_defaultsToNormalWhenUnset() {
        // Arrange
        let store = makeStore()

        // Act
        let speed = store.flightSpeed

        // Assert
        XCTAssertEqual(speed, .normal)
    }

    func test_roundTripsEachPreset() {
        // Arrange
        let store = makeStore()

        for preset in FlightSpeed.allCases {
            // Act
            store.flightSpeed = preset

            // Assert
            XCTAssertEqual(store.flightSpeed, preset)
        }
    }

    func test_persistsAcrossStoreInstancesSharingTheSameDefaults() {
        // Arrange
        let suiteName = "FlightSpeedStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = UserDefaultsFlightSpeedStore(defaults: defaults)

        // Act
        store.flightSpeed = .slow
        let relaunchedStore = UserDefaultsFlightSpeedStore(defaults: defaults)

        // Assert
        XCTAssertEqual(relaunchedStore.flightSpeed, .slow)
    }

    func test_flightDurationOrdering() {
        // Arrange / Act / Assert
        XCTAssertGreaterThan(FlightSpeed.slow.flightDuration, FlightSpeed.normal.flightDuration)
        XCTAssertGreaterThan(FlightSpeed.normal.flightDuration, FlightSpeed.fast.flightDuration)
    }
}
