import Foundation

/// Translates a **legacy** Google Calendar color hex — the value `calendarList.backgroundColor`
/// returns over the API — into the hex Google Calendar's own UI actually paints for that
/// color (AYD-012). The Calendar API still serves the pre-2018 pastel palette; picking a
/// color by name in the UI paints the newer Material palette instead, so the two hexes for
/// the same color (e.g. Peacock: `#9fe1e7` vs `#039be5`) differ. Painting the raw API value
/// makes the Banner a visibly different, paler tone than its Calendar.
///
/// Exact match only: a Calendar colored outside the standard 24 (a custom hex) already
/// reports the color the UI paints, so anything not in the table passes through unchanged
/// rather than snapping to the nearest palette entry.
enum CalendarPalette {
    /// Legacy hex (as the API returns it, normalized: lowercase, no `#`) → displayed hex
    /// (as Google Calendar's UI paints it, `#`-prefixed). Transcribed from AYD-012.
    private static let legacyToDisplayed: [String: String] = [
        "ac725e": "#795548", // Cocoa
        "d06b64": "#e67c73", // Flamingo
        "f83a22": "#d50000", // Tomato
        "fa573c": "#f4511e", // Tangerine
        "ff7537": "#ef6c00", // Pumpkin
        "ffad46": "#f09300", // Mango
        "42d692": "#009688", // Eucalyptus
        "16a765": "#0b8043", // Basil
        "7bd148": "#7cb342", // Pistachio
        "b3dc6c": "#c0ca33", // Avocado
        "fbe983": "#e4c441", // Citron
        "fad165": "#f6bf26", // Banana
        "92e1c0": "#33b679", // Sage
        "9fe1e7": "#039be5", // Peacock
        "9fc6e7": "#4285f4", // Cobalt
        "4986e7": "#3f51b5", // Blueberry
        "9a9cff": "#7986cb", // Lavender
        "b99aff": "#b39ddb", // Wisteria
        "c2c2c2": "#616161", // Graphite
        "cabdbf": "#a79b8e", // Birch
        "cca6ac": "#ad1457", // Radicchio
        "f691b2": "#d81b60", // Cherry Blossom
        "cd74e6": "#8e24aa", // Grape
        "a47ae2": "#9e69af", // Amethyst
    ]

    /// The hex Google Calendar's UI paints for `calendarColorHex`. Matches case-insensitively
    /// and with or without a leading `#`; anything not in the standard palette (a custom
    /// color, or an already-malformed value) is returned unchanged.
    static func displayedHex(for calendarColorHex: String) -> String {
        var digits = calendarColorHex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if digits.hasPrefix("#") {
            digits.removeFirst()
        }
        return legacyToDisplayed[digits] ?? calendarColorHex
    }
}
