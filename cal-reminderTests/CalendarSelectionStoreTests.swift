import XCTest
@testable import cal_reminder

final class CalendarSelectionStoreTests: XCTestCase {
    private func makeStore(accountId: String = "google:test-account") -> UserDefaultsCalendarSelectionStore {
        let suiteName = "CalendarSelectionStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return UserDefaultsCalendarSelectionStore(accountId: accountId, defaults: defaults)
    }

    func test_defaultsToNilWhenUnset() {
        let store = makeStore()

        XCTAssertNil(store.selectedCalendarIds)
    }

    func test_nilSelectionIsEffectivelyAllCalendars() {
        let store = makeStore()
        let allIds: Set<String> = ["A", "B", "C"]

        for id in allIds {
            XCTAssertTrue(store.isSelected(id, within: allIds))
        }
    }

    func test_deselectingOneKeepsOthersEffectivelySelected() {
        let store = makeStore()
        let allIds: Set<String> = ["A", "B", "C"]

        store.setSelected("B", false, within: allIds)

        XCTAssertEqual(store.selectedCalendarIds, ["A", "C"])
        XCTAssertTrue(store.isSelected("A", within: allIds))
        XCTAssertFalse(store.isSelected("B", within: allIds))
        XCTAssertTrue(store.isSelected("C", within: allIds))
    }

    func test_reselectingAfterDeselectRestoresIt() {
        let store = makeStore()
        let allIds: Set<String> = ["A", "B"]
        store.setSelected("B", false, within: allIds)

        store.setSelected("B", true, within: allIds)

        XCTAssertTrue(store.isSelected("B", within: allIds))
    }

    func test_persistsAcrossStoreInstancesSharingTheSameDefaults() {
        let suiteName = "CalendarSelectionStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = UserDefaultsCalendarSelectionStore(accountId: "google:test-account", defaults: defaults)

        store.setSelected("B", false, within: ["A", "B", "C"])
        let relaunchedStore = UserDefaultsCalendarSelectionStore(accountId: "google:test-account", defaults: defaults)

        XCTAssertEqual(relaunchedStore.selectedCalendarIds, ["A", "C"])
    }

    func test_selectionsAreIsolatedPerAccount() {
        let suiteName = "CalendarSelectionStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let storeA = UserDefaultsCalendarSelectionStore(accountId: "google:a", defaults: defaults)
        let storeB = UserDefaultsCalendarSelectionStore(accountId: "google:b", defaults: defaults)

        storeA.setSelected("Cal1", false, within: ["Cal1", "Cal2"])

        XCTAssertEqual(storeA.selectedCalendarIds, ["Cal2"])
        XCTAssertNil(storeB.selectedCalendarIds)
    }

    func test_legacyUnscopedKeyIsStillReadable() {
        let suiteName = "CalendarSelectionStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(["A", "C"], forKey: UserDefaultsCalendarSelectionStore.legacyKey)

        let stored = defaults.array(forKey: UserDefaultsCalendarSelectionStore.legacyKey) as? [String]

        XCTAssertEqual(Set(stored ?? []), ["A", "C"])
    }

    func test_staleStoredIdIsIntersectedOutByCaller() {
        let store = makeStore()
        store.setSelected("removed", true, within: ["removed"])

        let effective = store.selectedCalendarIds?.intersection(["A", "B"]) ?? ["A", "B"]

        XCTAssertTrue(effective.isEmpty)
    }
}
