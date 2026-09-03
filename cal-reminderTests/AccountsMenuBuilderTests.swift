import XCTest
@testable import cal_reminder

private final class FakeCalendarSelectionStore: CalendarSelectionStoring {
    var selectedCalendarIds: Set<String>?
}

final class AccountsMenuBuilderTests: XCTestCase {
    private func accountState(
        id: String,
        label: String,
        status: ConnectionStatus,
        calendars: [CalendarInfo] = []
    ) -> AccountState {
        AccountState(id: id, label: label, connectionStatus: status, calendars: calendars)
    }

    private func accountsMenu(for accounts: [AccountState]) -> NSMenu {
        AccountsMenuBuilder.accountsMenu(
            for: accounts,
            selectionStore: { _ in FakeCalendarSelectionStore() },
            actions: AccountsMenuActions(
                onCalendarsChanged: {},
                onReconnect: { _ in },
                onSignOut: { _ in },
                onAddAccount: {}
            )
        )
    }

    func test_noAccountsRendersOnlyAddAccount() {
        let menu = accountsMenu(for: [])

        XCTAssertEqual(menu.items.count, 1)
        XCTAssertEqual(menu.items.first?.title, "Add Google account…")
    }

    func test_rowCountMatchesAccountsPlusSeparatorPlusAddAccount() {
        let accounts = [
            accountState(id: "google:a", label: "a@example.com", status: .connected),
            accountState(id: "google:b", label: "b@example.com", status: .connected)
        ]

        let menu = accountsMenu(for: accounts)

        XCTAssertEqual(menu.items.count, 4)
        XCTAssertEqual(menu.items[0].title, "a@example.com")
        XCTAssertEqual(menu.items[1].title, "b@example.com")
        XCTAssertTrue(menu.items[2].isSeparatorItem)
        XCTAssertEqual(menu.items[3].title, "Add Google account…")
    }

    func test_needsReauthAccountTitleCarriesAWarningMarker() throws {
        let accounts = [accountState(id: "google:a", label: "a@example.com", status: .needsReauth)]

        let menu = accountsMenu(for: accounts)

        let title = try XCTUnwrap(menu.items.first?.title)
        XCTAssertTrue(title.contains("a@example.com"))
        XCTAssertTrue(title.contains("⚠︎"))
    }

    func test_connectedAccountTitleHasNoWarningMarker() {
        let accounts = [accountState(id: "google:a", label: "a@example.com", status: .connected)]

        let menu = accountsMenu(for: accounts)

        XCTAssertEqual(menu.items.first?.title, "a@example.com")
    }

    func test_accountSubmenuContainsCalendarsSeparatorReconnectAndSignOut() throws {
        let accounts = [accountState(id: "google:a", label: "a@example.com", status: .connected)]

        let menu = accountsMenu(for: accounts)
        let accountSubmenu = try XCTUnwrap(menu.items.first?.submenu)

        XCTAssertEqual(accountSubmenu.items.count, 4)
        XCTAssertEqual(accountSubmenu.items[0].title, "Calendars")
        XCTAssertTrue(accountSubmenu.items[1].isSeparatorItem)
        XCTAssertEqual(accountSubmenu.items[2].title, "Reconnect")
        XCTAssertEqual(accountSubmenu.items[3].title, "Sign out")
    }

    func test_calendarsSubmenuShowsPlaceholderWhenEmpty() {
        let account = accountState(id: "google:a", label: "a@example.com", status: .connected, calendars: [])

        let submenu = AccountsMenuBuilder.calendarsSubmenu(
            for: account,
            selectionStore: FakeCalendarSelectionStore(),
            onCalendarsChanged: {}
        )

        XCTAssertEqual(submenu.items.count, 1)
        XCTAssertEqual(submenu.items.first?.title, "No Calendars yet")
        XCTAssertFalse(submenu.items.first?.isEnabled ?? true)
    }

    func test_calendarsSubmenuHasOneRowPerCalendar() {
        let account = accountState(
            id: "google:a",
            label: "a@example.com",
            status: .connected,
            calendars: [
                CalendarInfo(id: "cal1", title: "Cal 1", isPrimary: true),
                CalendarInfo(id: "cal2", title: "Cal 2", isPrimary: false)
            ]
        )

        let submenu = AccountsMenuBuilder.calendarsSubmenu(
            for: account,
            selectionStore: FakeCalendarSelectionStore(),
            onCalendarsChanged: {}
        )

        XCTAssertEqual(submenu.items.count, 2)
        XCTAssertNotNil(submenu.items[0].view)
        XCTAssertNotNil(submenu.items[1].view)
    }
}
