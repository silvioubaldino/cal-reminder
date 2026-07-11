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
        // Arrange
        let screenWidth: CGFloat = 1920

        // Act / Assert
        XCTAssertGreaterThan(
            FlightSpeed.slow.flightDuration(forScreenWidth: screenWidth),
            FlightSpeed.normal.flightDuration(forScreenWidth: screenWidth)
        )
        XCTAssertGreaterThan(
            FlightSpeed.normal.flightDuration(forScreenWidth: screenWidth),
            FlightSpeed.fast.flightDuration(forScreenWidth: screenWidth)
        )
    }

    func test_flightDurationScalesWithScreenWidth() {
        // Arrange / Act
        let narrow = FlightSpeed.normal.flightDuration(forScreenWidth: 800)
        let wide = FlightSpeed.normal.flightDuration(forScreenWidth: 3440) // ultrawide

        // Assert: same preset takes longer, in real time, to cross a wider screen —
        // but at the same visual (points-per-second) speed.
        XCTAssertGreaterThan(wide, narrow)
    }
}
