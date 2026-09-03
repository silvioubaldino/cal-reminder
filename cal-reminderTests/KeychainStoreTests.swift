import XCTest
@testable import cal_reminder

final class KeychainStoreTests: XCTestCase {
    private func makeStore() -> KeychainStore {
        KeychainStore(service: "com.cal-reminder.auth.tests.\(UUID().uuidString)")
    }

    func test_returnsNilWhenNeverSet() {
        let store = makeStore()

        let token = store.refreshToken()

        XCTAssertNil(token)
    }

    func test_roundTripsAToken() {
        let store = makeStore()

        store.setRefreshToken("refresh-token-value")

        XCTAssertEqual(store.refreshToken(), "refresh-token-value")
    }

    func test_overwritesAPreviouslyStoredToken() {
        let store = makeStore()
        store.setRefreshToken("first-token")

        store.setRefreshToken("second-token")

        XCTAssertEqual(store.refreshToken(), "second-token")
    }

    func test_settingNilDeletesTheToken() {
        let store = makeStore()
        store.setRefreshToken("some-token")

        store.setRefreshToken(nil)

        XCTAssertNil(store.refreshToken())
    }

    func test_twoAccountsUnderTheSameServiceDontSeeEachOthersToken() {
        let service = "com.cal-reminder.auth.tests.\(UUID().uuidString)"
        let storeA = KeychainStore(service: service, account: KeychainStore.accountScopedKey("google:a"))
        let storeB = KeychainStore(service: service, account: KeychainStore.accountScopedKey("google:b"))

        storeA.setRefreshToken("token-a")

        XCTAssertEqual(storeA.refreshToken(), "token-a")
        XCTAssertNil(storeB.refreshToken())
    }

    func test_defaultAccountStillReadsTheLegacyUnscopedEntry() {
        let service = "com.cal-reminder.auth.tests.\(UUID().uuidString)"
        let legacyStore = KeychainStore(service: service)

        legacyStore.setRefreshToken("legacy-token")
        let reopened = KeychainStore(service: service, account: KeychainStore.legacyAccount)

        XCTAssertEqual(reopened.refreshToken(), "legacy-token")
    }
}
