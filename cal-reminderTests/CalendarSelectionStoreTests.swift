import XCTest
@testable import cal_reminder

final class CalendarSelectionStoreTests: XCTestCase {
    private func makeStore(accountId: String = "google:test-account") -> UserDefaultsCalendarSelectionStore {
        let suiteName = "CalendarSelectionStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return UserDefaultsCalendarSelectionStore(accountId: accountId, defaults: defaults)
    }

    func test_defaultsToNilWhenUnset() {
        // Arrange
        let store = makeStore()

        // Act / Assert
        XCTAssertNil(store.selectedCalendarIds)
    }

    func test_nilSelectionIsEffectivelyAllCalendars() {
        // Arrange (RF-10 default: never chosen → all)
        let store = makeStore()
        let allIds: Set<String> = ["A", "B", "C"]

        // Act / Assert
        for id in allIds {
            XCTAssertTrue(store.isSelected(id, within: allIds))
        }
    }

    func test_deselectingOneKeepsOthersEffectivelySelected() {
        // Arrange
        let store = makeStore()
        let allIds: Set<String> = ["A", "B", "C"]

        // Act
        store.setSelected("B", false, within: allIds)

        // Assert
        XCTAssertEqual(store.selectedCalendarIds, ["A", "C"])
        XCTAssertTrue(store.isSelected("A", within: allIds))
        XCTAssertFalse(store.isSelected("B", within: allIds))
        XCTAssertTrue(store.isSelected("C", within: allIds))
    }

    func test_reselectingAfterDeselectRestoresIt() {
        // Arrange
        let store = makeStore()
        let allIds: Set<String> = ["A", "B"]
        store.setSelected("B", false, within: allIds)

        // Act
        store.setSelected("B", true, within: allIds)

        // Assert
        XCTAssertTrue(store.isSelected("B", within: allIds))
    }

    func test_persistsAcrossStoreInstancesSharingTheSameDefaults() {
        // Arrange
        let suiteName = "CalendarSelectionStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = UserDefaultsCalendarSelectionStore(accountId: "google:test-account", defaults: defaults)

        // Act
        store.setSelected("B", false, within: ["A", "B", "C"])
        let relaunchedStore = UserDefaultsCalendarSelectionStore(accountId: "google:test-account", defaults: defaults)

        // Assert
        XCTAssertEqual(relaunchedStore.selectedCalendarIds, ["A", "C"])
    }

    func test_selectionsAreIsolatedPerAccount() {
        // Arrange (RF-14: each Account's Calendar selection is independent)
        let suiteName = "CalendarSelectionStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let storeA = UserDefaultsCalendarSelectionStore(accountId: "google:a", defaults: defaults)
        let storeB = UserDefaultsCalendarSelectionStore(accountId: "google:b", defaults: defaults)

        // Act
        storeA.setSelected("Cal1", false, within: ["Cal1", "Cal2"])

        // Assert
        XCTAssertEqual(storeA.selectedCalendarIds, ["Cal2"])
        XCTAssertNil(storeB.selectedCalendarIds)
    }

    func test_legacyUnscopedKeyIsStillReadable() {
        // Arrange: a pre-multi-account install stored its selection under the bare,
        // unscoped key — the migration path reads it directly via that literal key (TDR-005).
        let suiteName = "CalendarSelectionStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(["A", "C"], forKey: UserDefaultsCalendarSelectionStore.legacyKey)

        // Act
        let stored = defaults.array(forKey: UserDefaultsCalendarSelectionStore.legacyKey) as? [String]

        // Assert
        XCTAssertEqual(Set(stored ?? []), ["A", "C"])
    }

    func test_staleStoredIdIsIntersectedOutByCaller() {
        // Arrange: a Calendar removed/unshared since the selection was stored.
        let store = makeStore()
        store.setSelected("removed", true, within: ["removed"])

        // Act
        let effective = store.selectedCalendarIds?.intersection(["A", "B"]) ?? ["A", "B"]

        // Assert
        XCTAssertTrue(effective.isEmpty)
    }
}
