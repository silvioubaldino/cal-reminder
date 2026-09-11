import XCTest
@testable import cal_reminder

final class CalendarPaletteTests: XCTestCase {
    /// The full legacy → displayed table from AYD-012, kept in sync with `CalendarPalette`
    /// so a transcription slip on either side fails this test.
    private static let table: [(legacy: String, displayed: String)] = [
        ("ac725e", "#795548"), // Cocoa
        ("d06b64", "#e67c73"), // Flamingo
        ("f83a22", "#d50000"), // Tomato
        ("fa573c", "#f4511e"), // Tangerine
        ("ff7537", "#ef6c00"), // Pumpkin
        ("ffad46", "#f09300"), // Mango
        ("42d692", "#009688"), // Eucalyptus
        ("16a765", "#0b8043"), // Basil
        ("7bd148", "#7cb342"), // Pistachio
        ("b3dc6c", "#c0ca33"), // Avocado
        ("fbe983", "#e4c441"), // Citron
        ("fad165", "#f6bf26"), // Banana
        ("92e1c0", "#33b679"), // Sage
        ("9fe1e7", "#039be5"), // Peacock
        ("9fc6e7", "#4285f4"), // Cobalt
        ("4986e7", "#3f51b5"), // Blueberry
        ("9a9cff", "#7986cb"), // Lavender
        ("b99aff", "#b39ddb"), // Wisteria
        ("c2c2c2", "#616161"), // Graphite
        ("cabdbf", "#a79b8e"), // Birch
        ("cca6ac", "#ad1457"), // Radicchio
        ("f691b2", "#d81b60"), // Cherry Blossom
        ("cd74e6", "#8e24aa"), // Grape
        ("a47ae2", "#9e69af"), // Amethyst
    ]

    func test_hasExactlyTwentyFourEntriesWithNoDuplicates() {
        // Arrange
        let legacyKeys = Set(Self.table.map(\.legacy))
        let displayedValues = Set(Self.table.map(\.displayed))

        // Act / Assert
        XCTAssertEqual(Self.table.count, 24)
        XCTAssertEqual(legacyKeys.count, 24, "duplicate legacy key in the table")
        XCTAssertEqual(displayedValues.count, 24, "duplicate displayed value in the table")
    }

    func test_translatesEveryStandardCalendarColor() {
        for entry in Self.table {
            // Act
            let result = CalendarPalette.displayedHex(for: entry.legacy)

            // Assert
            XCTAssertEqual(result, entry.displayed, "mismatch for legacy hex \(entry.legacy)")
        }
    }

    func test_matchesRegardlessOfCaseAndLeadingHash() {
        // Arrange / Act / Assert
        XCTAssertEqual(CalendarPalette.displayedHex(for: "9FE1E7"), "#039be5")
        XCTAssertEqual(CalendarPalette.displayedHex(for: "#9fe1e7"), "#039be5")
        XCTAssertEqual(CalendarPalette.displayedHex(for: "#9FE1E7"), "#039be5")
    }

    func test_passesThroughAnythingNotInThePalette() {
        // Arrange / Act / Assert — a custom Calendar color, an empty string, and a
        // malformed value must all come back unchanged, never snapped to a nearest color.
        XCTAssertEqual(CalendarPalette.displayedHex(for: "#123456"), "#123456")
        XCTAssertEqual(CalendarPalette.displayedHex(for: ""), "")
        XCTAssertEqual(CalendarPalette.displayedHex(for: "not-a-color"), "not-a-color")
    }
}
