import XCTest
@testable import cal_reminder

private final class FakeReminderSettingsStore: ReminderSettingsStoring {
    var settings: ReminderSettings
    init(_ settings: ReminderSettings = .default) {
        self.settings = settings
    }
}

final class RemindersMenuTests: XCTestCase {
    /// Held by the test case: `NSMenuItem.target` is weak, so the menu's owner has to stay
    /// alive for the actions to reach it.
    private var remindersMenu: RemindersMenu!

    override func tearDown() {
        remindersMenu = nil
        super.tearDown()
    }

    private func makeMenu(
        _ settings: ReminderSettings = .default,
        onRemindersChanged: @escaping () -> Void = {}
    ) -> (item: NSMenuItem, store: FakeReminderSettingsStore) {
        let store = FakeReminderSettingsStore(settings)
        remindersMenu = RemindersMenu(store: store, onRemindersChanged: onRemindersChanged)
        return (remindersMenu.menuItem, store)
    }

    private func click(_ item: NSMenuItem) throws {
        let target = try XCTUnwrap(item.target as? NSObject)
        let action = try XCTUnwrap(item.action)
        _ = target.perform(action, with: item)
    }

    private func extraItem(_ minutes: Int, in item: NSMenuItem) throws -> NSMenuItem {
        let submenu = try XCTUnwrap(item.submenu)
        return try XCTUnwrap(submenu.items.first { $0.representedObject as? Int == minutes })
    }

    func test_submenuListsInheritedRowThenEveryPreset() throws {
        // Arrange + Act
        let (item, _) = makeMenu()

        // Assert
        let submenu = try XCTUnwrap(item.submenu)
        XCTAssertEqual(submenu.items[0].title, "Event's own reminders")
        XCTAssertTrue(submenu.items[1].isSeparatorItem)
        XCTAssertEqual(submenu.items[2].title, "Always add:")
        XCTAssertFalse(submenu.items[2].isEnabled)
        XCTAssertEqual(
            submenu.items[3...7].map(\.title),
            ["At start time", "1 minute before", "5 minutes before", "10 minutes before", "15 minutes before"]
        )
    }

    func test_checkmarksMirrorTheStoredSelection() throws {
        // Arrange + Act
        let (item, _) = makeMenu(ReminderSettings(inheritEventReminders: false, extraMinutes: [1, 15]))

        // Assert
        let submenu = try XCTUnwrap(item.submenu)
        XCTAssertEqual(submenu.items[0].state, .off)
        XCTAssertEqual(try extraItem(1, in: item).state, .on)
        XCTAssertEqual(try extraItem(15, in: item).state, .on)
        XCTAssertEqual(try extraItem(5, in: item).state, .off)
    }

    func test_titleStatesTheSelectionWithoutOpeningTheSubmenu() {
        // Arrange + Act
        let (item, _) = makeMenu(ReminderSettings(inheritEventReminders: true, extraMinutes: [1, 5]))

        // Assert
        XCTAssertEqual(item.title, "Reminders (calendar + 1, 5 min)")
    }

    func test_checkingAnExtraReminderPersistsRetitlesAndReportsTheChange() throws {
        // Arrange
        var changes = 0
        let (item, store) = makeMenu(onRemindersChanged: { changes += 1 })

        // Act
        try click(try extraItem(1, in: item))

        // Assert
        XCTAssertEqual(store.settings.extraMinutes, [1])
        XCTAssertEqual(try extraItem(1, in: item).state, .on)
        XCTAssertEqual(item.title, "Reminders (calendar + 1 min)")
        XCTAssertEqual(changes, 1)
    }

    func test_clickingACheckedExtraReminderUnchecksIt() throws {
        // Arrange
        let (item, store) = makeMenu(ReminderSettings(inheritEventReminders: true, extraMinutes: [5]))

        // Act
        try click(try extraItem(5, in: item))

        // Assert
        XCTAssertTrue(store.settings.extraMinutes.isEmpty)
        XCTAssertEqual(try extraItem(5, in: item).state, .off)
    }

    func test_togglingTheInheritedRowPersistsAndReportsTheChange() throws {
        // Arrange
        var changes = 0
        let (item, store) = makeMenu(onRemindersChanged: { changes += 1 })
        let submenu = try XCTUnwrap(item.submenu)

        // Act
        try click(submenu.items[0])

        // Assert
        XCTAssertFalse(store.settings.inheritEventReminders)
        XCTAssertEqual(submenu.items[0].state, .off)
        XCTAssertEqual(changes, 1)
    }

    func test_emptySelectionIsStatedInTheTitleAndWarnedAboutInTheSubmenu() throws {
        // Arrange
        let (item, _) = makeMenu(ReminderSettings(inheritEventReminders: false, extraMinutes: [1]))
        let submenu = try XCTUnwrap(item.submenu)

        // Act — unchecking the last Reminder leaves nothing selected
        try click(try extraItem(1, in: item))

        // Assert
        XCTAssertEqual(item.title, "Reminders (none)")
        let warning = try XCTUnwrap(submenu.items.last)
        XCTAssertTrue(warning.title.contains("⚠︎"))
        XCTAssertTrue(warning.title.contains("nothing will fly"))
        XCTAssertFalse(warning.isEnabled)
    }

    func test_warningDisappearsOnceSomethingIsSelectedAgain() throws {
        // Arrange
        let (item, _) = makeMenu(ReminderSettings(inheritEventReminders: false, extraMinutes: []))
        let submenu = try XCTUnwrap(item.submenu)
        let rowsWithWarning = submenu.items.count

        // Act
        try click(try extraItem(5, in: item))

        // Assert
        XCTAssertEqual(submenu.items.count, rowsWithWarning - 2, "the warning row and its separator are removed")
        XCTAssertFalse(submenu.items.contains { $0.title.contains("nothing will fly") })
        XCTAssertEqual(item.title, "Reminders (5 min)")
    }
}
