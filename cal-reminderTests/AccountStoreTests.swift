import XCTest
@testable import cal_reminder

final class AccountStoreTests: XCTestCase {
    private func makeStore() -> UserDefaultsAccountStore {
        let suiteName = "AccountStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return UserDefaultsAccountStore(defaults: defaults)
    }

    func test_defaultsToEmptyWhenUnset() {
        let store = makeStore()

        XCTAssertEqual(store.accounts, [])
    }

    func test_roundTripsAccounts() {
        let store = makeStore()
        let accounts = [
            Account(id: "google:a", provider: .google, label: "a@example.com"),
            Account(id: "google:b", provider: .google, label: "b@example.com")
        ]

        store.accounts = accounts

        XCTAssertEqual(store.accounts, accounts)
    }

    func test_preservesInsertionOrder() {
        let store = makeStore()
        let accounts = [
            Account(id: "google:c", provider: .google, label: "c@example.com"),
            Account(id: "google:a", provider: .google, label: "a@example.com"),
            Account(id: "google:b", provider: .google, label: "b@example.com")
        ]

        store.accounts = accounts

        XCTAssertEqual(store.accounts.map(\.id), ["google:c", "google:a", "google:b"])
    }

    func test_persistsAcrossStoreInstancesSharingTheSameDefaults() {
        let suiteName = "AccountStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = UserDefaultsAccountStore(defaults: defaults)
        let account = Account(id: "google:a", provider: .google, label: "a@example.com")

        store.accounts = [account]
        let relaunchedStore = UserDefaultsAccountStore(defaults: defaults)

        XCTAssertEqual(relaunchedStore.accounts, [account])
    }
}
