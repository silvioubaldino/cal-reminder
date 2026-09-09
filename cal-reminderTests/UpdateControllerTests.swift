import XCTest
@testable import cal_reminder

private final class FakeUpdateSettingsStore: UpdateSettingsStoring {
    var automaticallyChecks = false
}

private final class FakeSparkleUpdater: SparkleUpdating {
    var automaticallyChecksForUpdates = false
    var checkForUpdatesCallCount = 0

    func checkForUpdates() {
        checkForUpdatesCallCount += 1
    }
}

private final class FakeUpdating: Updating {
    var isConfigured: Bool
    var automaticallyChecks: Bool
    var currentVersion: String
    var checkForUpdatesCallCount = 0

    init(isConfigured: Bool, automaticallyChecks: Bool = false, currentVersion: String = "1.2.0") {
        self.isConfigured = isConfigured
        self.automaticallyChecks = automaticallyChecks
        self.currentVersion = currentVersion
    }

    func checkForUpdates() {
        checkForUpdatesCallCount += 1
    }
}

final class UpdateControllerTests: XCTestCase {
    // MARK: UpdateConfiguration.make

    func test_make_returnsConfiguration_forTwoRealValues() {
        let config = UpdateConfiguration.make(feedURL: "https://example.com/appcast.xml", publicKey: "abc123")

        XCTAssertEqual(config?.feedURL, "https://example.com/appcast.xml")
        XCTAssertEqual(config?.publicKey, "abc123")
    }

    func test_make_nil_whenFeedURLMissing() {
        XCTAssertNil(UpdateConfiguration.make(feedURL: nil, publicKey: "abc123"))
    }

    func test_make_nil_whenPublicKeyMissing() {
        XCTAssertNil(UpdateConfiguration.make(feedURL: "https://example.com/appcast.xml", publicKey: nil))
    }

    func test_make_nil_whenEmpty() {
        XCTAssertNil(UpdateConfiguration.make(feedURL: "", publicKey: ""))
    }

    func test_make_nil_whenWhitespaceOnly() {
        XCTAssertNil(UpdateConfiguration.make(feedURL: "   ", publicKey: "\n\t"))
    }

    // MARK: UpdateController

    func test_isConfigured_false_whenNoUpdater() {
        let controller = UpdateController(updater: nil, settingsStore: FakeUpdateSettingsStore())

        XCTAssertFalse(controller.isConfigured)
    }

    func test_isConfigured_true_whenUpdaterPresent() {
        let controller = UpdateController(updater: FakeSparkleUpdater(), settingsStore: FakeUpdateSettingsStore())

        XCTAssertTrue(controller.isConfigured)
    }

    func test_togglingAutomaticallyChecks_writesThroughToStoreAndUpdater() {
        // Arrange
        let updater = FakeSparkleUpdater()
        let store = FakeUpdateSettingsStore()
        let controller = UpdateController(updater: updater, settingsStore: store)

        // Act
        controller.automaticallyChecks = true

        // Assert
        XCTAssertTrue(store.automaticallyChecks)
        XCTAssertTrue(updater.automaticallyChecksForUpdates)
    }

    func test_checkForUpdates_activatesAppAndCallsThroughToUpdater() {
        // Arrange
        let updater = FakeSparkleUpdater()
        var activated = false
        let controller = UpdateController(
            updater: updater,
            settingsStore: FakeUpdateSettingsStore(),
            activateApp: { activated = true }
        )

        // Act
        controller.checkForUpdates()

        // Assert
        XCTAssertTrue(activated)
        XCTAssertEqual(updater.checkForUpdatesCallCount, 1)
    }

    func test_togglingAutomaticallyChecks_neverActivatesTheApp() {
        // Arrange
        let updater = FakeSparkleUpdater()
        var activated = false
        let controller = UpdateController(
            updater: updater,
            settingsStore: FakeUpdateSettingsStore(),
            activateApp: { activated = true }
        )

        // Act
        controller.automaticallyChecks = true

        // Assert
        XCTAssertFalse(activated)
    }

    // MARK: UpdateMenuBuilder

    func test_menuItems_configured_showsVersionCheckItemAndCheckbox() {
        let updater = FakeUpdating(isConfigured: true, automaticallyChecks: true, currentVersion: "1.2.0")

        let items = UpdateMenuBuilder.items(for: updater, onCheckForUpdates: {}, onToggleAutomaticChecks: {})

        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].title, "cal-reminder 1.2.0")
        XCTAssertFalse(items[0].isEnabled)
        XCTAssertEqual(items[1].title, "Check for updates…")
        XCTAssertTrue(items[1].isEnabled)
        XCTAssertEqual(items[2].state, .on)
    }

    func test_menuItems_sourceBuild_showsSingleDisabledRowAndNoCheckItem() {
        let updater = FakeUpdating(isConfigured: false)

        let items = UpdateMenuBuilder.items(for: updater, onCheckForUpdates: {}, onToggleAutomaticChecks: {})

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, "Updates: source build")
        XCTAssertFalse(items[0].isEnabled)
    }

    func test_menuItems_checkForUpdates_callsThrough() {
        let updater = FakeUpdating(isConfigured: true)
        var checkCalled = false

        let items = UpdateMenuBuilder.items(for: updater, onCheckForUpdates: { checkCalled = true }, onToggleAutomaticChecks: {})
        _ = items[1].target?.perform(items[1].action!, with: items[1])

        XCTAssertTrue(checkCalled)
    }
}
