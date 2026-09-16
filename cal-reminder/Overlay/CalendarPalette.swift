import Foundation

enum CalendarPalette {
    private static let legacyToDisplayed: [String: String] = [
        "ac725e": "#795548",
        "d06b64": "#e67c73",
        "f83a22": "#d50000",
        "fa573c": "#f4511e",
        "ff7537": "#ef6c00",
        "ffad46": "#f09300",
        "42d692": "#009688",
        "16a765": "#0b8043",
        "7bd148": "#7cb342",
        "b3dc6c": "#c0ca33",
        "fbe983": "#e4c441",
        "fad165": "#f6bf26",
        "92e1c0": "#33b679",
        "9fe1e7": "#039be5",
        "9fc6e7": "#4285f4",
        "4986e7": "#3f51b5",
        "9a9cff": "#7986cb",
        "b99aff": "#b39ddb",
        "c2c2c2": "#616161",
        "cabdbf": "#a79b8e",
        "cca6ac": "#ad1457",
        "f691b2": "#d81b60",
        "cd74e6": "#8e24aa",
        "a47ae2": "#9e69af"
    ]

    static func displayedHex(for calendarColorHex: String) -> String {
        var digits = calendarColorHex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if digits.hasPrefix("#") {
            digits.removeFirst()
        }
        return legacyToDisplayed[digits] ?? calendarColorHex
    }
}
