import AppKit
import XCTest
@testable import cal_reminder

private final class StubBannerColorStore: BannerColorStoring {
    var bannerColor: BannerColor
    init(bannerColor: BannerColor) { self.bannerColor = bannerColor }
}

private final class StubMatchCalendarColorStore: MatchCalendarColorStoring {
    var matchCalendarColor: Bool
    init(matchCalendarColor: Bool) { self.matchCalendarColor = matchCalendarColor }
}

final class BannerColorStoreTests: XCTestCase {
    private func makeStore() -> UserDefaultsBannerColorStore {
        let suiteName = "BannerColorStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return UserDefaultsBannerColorStore(defaults: defaults)
    }

    func test_defaultsToPinkWhenUnset() {
        // Arrange
        let store = makeStore()

        // Act
        let color = store.bannerColor

        // Assert
        XCTAssertEqual(color, .pink)
    }

    func test_roundTripsEachPreset() {
        // Arrange
        let store = makeStore()

        for preset in BannerColor.allCases {
            // Act
            store.bannerColor = preset

            // Assert
            XCTAssertEqual(store.bannerColor, preset)
        }
    }

    func test_persistsAcrossStoreInstancesSharingTheSameDefaults() {
        // Arrange
        let suiteName = "BannerColorStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = UserDefaultsBannerColorStore(defaults: defaults)

        // Act
        store.bannerColor = .blue
        let relaunchedStore = UserDefaultsBannerColorStore(defaults: defaults)

        // Assert
        XCTAssertEqual(relaunchedStore.bannerColor, .blue)
    }

    // MARK: - Calendar Color (RF-13)

    private func makeMatchStore() -> UserDefaultsMatchCalendarColorStore {
        let suiteName = "MatchCalendarColorStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return UserDefaultsMatchCalendarColorStore(defaults: defaults)
    }

    func test_matchCalendarColorDefaultsToOnWhenUnset() {
        // Arrange
        let store = makeMatchStore()

        // Act
        let matches = store.matchCalendarColor

        // Assert
        XCTAssertTrue(matches)
    }

    func test_matchCalendarColorRoundTripsAcrossStoreInstances() {
        // Arrange
        let suiteName = "MatchCalendarColorStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = UserDefaultsMatchCalendarColorStore(defaults: defaults)

        // Act
        store.matchCalendarColor = false
        let relaunchedStore = UserDefaultsMatchCalendarColorStore(defaults: defaults)

        // Assert
        XCTAssertFalse(relaunchedStore.matchCalendarColor)
    }

    func test_parsesCalendarColorHexWithAndWithoutHash() throws {
        // Arrange
        let withHash = try XCTUnwrap(NSColor(bannerHex: "#0088aa")?.usingColorSpace(.sRGB))
        let withoutHash = try XCTUnwrap(NSColor(bannerHex: "0088aa")?.usingColorSpace(.sRGB))

        // Act / Assert
        for color in [withHash, withoutHash] {
            XCTAssertEqual(color.redComponent, 0x00 / 255.0, accuracy: 0.001)
            XCTAssertEqual(color.greenComponent, 0x88 / 255.0, accuracy: 0.001)
            XCTAssertEqual(color.blueComponent, 0xAA / 255.0, accuracy: 0.001)
        }
    }

    func test_rejectsMalformedCalendarColorHex() {
        // Arrange / Act / Assert
        XCTAssertNil(NSColor(bannerHex: ""))
        XCTAssertNil(NSColor(bannerHex: "#12345"))
        XCTAssertNil(NSColor(bannerHex: "#zzzzzz"))
        XCTAssertNil(NSColor(bannerHex: "rgb(1,2,3)"))
    }

    func test_bannerTextColorContrastsWithTheBanner() throws {
        // Arrange
        let darkBanner = try XCTUnwrap(NSColor(bannerHex: "#0b8043"))
        let lightBanner = try XCTUnwrap(NSColor(bannerHex: "#fbe983"))

        // Act
        let onDark = try XCTUnwrap(darkBanner.readableBannerTextColor.usingColorSpace(.sRGB))
        let onLight = try XCTUnwrap(lightBanner.readableBannerTextColor.usingColorSpace(.sRGB))

        // Assert
        XCTAssertEqual(onDark.brightnessComponent, 1, accuracy: 0.01)
        XCTAssertLessThan(onLight.brightnessComponent, 0.2)
    }

    func test_convertsTheCalendarColorToTheDisplaysColorSpaceWithoutShiftingIt() throws {
        // Arrange (TDR-004: sRGB components painted raw on a P3 display read oversaturated)
        let calendarColor = try XCTUnwrap(NSColor(bannerHex: "#0b8043"))

        // Act
        let onWideGamut = calendarColor.matchingDisplayColorSpace(.displayP3)
        let onSRGB = try XCTUnwrap(calendarColor.matchingDisplayColorSpace(.sRGB).usingColorSpace(.sRGB))
        let untouched = calendarColor.matchingDisplayColorSpace(nil)

        // Assert — the components change with the space, but the color itself doesn't:
        // converted back to sRGB it is the Calendar Color again.
        XCTAssertEqual(onWideGamut.colorSpace, .displayP3)
        XCTAssertNotEqual(onWideGamut.greenComponent, 0x80 / 255.0, accuracy: 0.001)
        let roundTripped = try XCTUnwrap(onWideGamut.usingColorSpace(.sRGB))
        XCTAssertEqual(roundTripped.redComponent, 0x0B / 255.0, accuracy: 0.005)
        XCTAssertEqual(roundTripped.greenComponent, 0x80 / 255.0, accuracy: 0.005)
        XCTAssertEqual(roundTripped.blueComponent, 0x43 / 255.0, accuracy: 0.005)
        XCTAssertEqual(onSRGB.greenComponent, 0x80 / 255.0, accuracy: 0.001)
        XCTAssertEqual(untouched, calendarColor)
    }

    @MainActor
    func test_usesTheCalendarColorOnlyWhileMatchingIsOn() throws {
        // Arrange
        func animator(matching: Bool) -> DefaultOverlayAnimator {
            DefaultOverlayAnimator(
                colorStore: StubBannerColorStore(bannerColor: .blue),
                matchCalendarColorStore: StubMatchCalendarColorStore(matchCalendarColor: matching)
            )
        }

        // Act
        let matched = try XCTUnwrap(animator(matching: true).bannerBackgroundColor(for: "#0b8043").usingColorSpace(.sRGB))
        let unmatched = animator(matching: false).bannerBackgroundColor(for: "#0b8043")
        let colorless = animator(matching: true).bannerBackgroundColor(for: nil)
        let malformed = animator(matching: true).bannerBackgroundColor(for: "not-a-color")

        // Assert
        XCTAssertEqual(matched.greenComponent, 0x80 / 255.0, accuracy: 0.001)
        XCTAssertEqual(unmatched, BannerColor.blue.color)
        XCTAssertEqual(colorless, BannerColor.blue.color)
        XCTAssertEqual(malformed, BannerColor.blue.color)
    }
}
