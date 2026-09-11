---
id: SPEC-022
type: spec
status: draft
updated: 2026-09-11
parents: [AYD-012]
related: [GLO, TDR-004, SPEC-014]
---

# SPEC-022: Paint the Banner with the Calendar Color Google displays — what + how

## What (goal)
Translate the legacy palette hex the Calendar API returns into the hex Google Calendar
actually paints, so a Banner and its Calendar are the same color side by side (RF-13).

## Acceptance criteria
```gherkin
Scenario: A standard palette color is painted as Google displays it
  Given the "Match calendar color" toggle is on
  And a Trigger whose Calendar Color is "#9fe1e7" (Peacock, as the API returns it)
  When the Banner's background color is resolved
  Then it is the color "#039be5", not "#9fe1e7"

Scenario: Every standard Calendar color is translated
  Given each of the 24 legacy calendar-palette hexes
  When each is resolved
  Then each yields its displayed counterpart from the AYD-012 table

Scenario: A custom Calendar color is left alone
  Given a Trigger whose Calendar Color is "#123456", not a palette entry
  When the Banner's background color is resolved
  Then it is the color "#123456"

Scenario: The hex is matched regardless of case and leading '#'
  Given a Trigger whose Calendar Color is "9FE1E7"
  When the Banner's background color is resolved
  Then it is the color "#039be5"

Scenario: Text contrast follows the translated color
  Given a Trigger whose Calendar Color is "#9fe1e7"
  When the Banner's colors are resolved
  Then the Banner text is white, the readable choice against "#039be5"

Scenario: The toggle still wins
  Given the "Match calendar color" toggle is off
  And a Trigger whose Calendar Color is "#9fe1e7"
  When the Banner's background color is resolved
  Then it is the chosen Banner color preset

Scenario: No Calendar Color still falls back to the preset
  Given a Trigger with no Calendar Color
  When the Banner's background color is resolved
  Then it is the chosen Banner color preset
```

## How (approach)
A new `CalendarPalette` type holds the 24-entry legacy → displayed table and exposes one pure
function, `displayedHex(for:)`, that exact-matches on the normalized hex and passes anything
else through. `DefaultOverlayAnimator.bannerBackgroundColor(for:)` runs the Trigger's hex
through it before parsing. Nothing else moves: the toggle, the preset fallback, the derived
text color and TDR-004's display-color-space conversion all keep working on the result.

## Steps
1. Add `cal-reminder/Overlay/CalendarPalette.swift`: a `[String: String]` table keyed by the
   normalized legacy hex (lowercase, no `#`), plus `displayedHex(for:)` and the normalizer.
   Transcribe the table from AYD-012 verbatim; keep the color name as a comment per row.
2. **Verify the table against the source before merging** (see Tests): the two anchors
   (Peacock, Cobalt) at minimum, ideally by reading a Calendar of each color through the API
   and reading the swatch Google Calendar paints for it.
3. In `DefaultOverlayAnimator.bannerBackgroundColor(for:)`, wrap the hex:
   `NSColor(bannerHex: CalendarPalette.displayedHex(for: calendarColorHex))`. Do not touch
   the toggle check, the preset fallback, or the call order around TDR-004's
   `matchingDisplayColorSpace(_:)`.
4. Add the tests below.
5. One line in `docs/changelog.md`.

## Affected files
- `cal-reminder/Overlay/CalendarPalette.swift` *(new)*
- `cal-reminder/Overlay/OverlayPresenter.swift`
- `cal-reminderTests/CalendarPaletteTests.swift` *(new)*
- `cal-reminderTests/BannerColorStoreTests.swift` (or wherever the animator's color
  resolution is already covered)
- `project.yml` / the Xcode project, if sources are not globbed
- `docs/changelog.md`

## Tests
- **Acceptance:** one test per Gherkin scenario above, driven through
  `DefaultOverlayAnimator.bannerBackgroundColor(for:)` with faked stores — no screen needed,
  since the display-color-space step is applied after resolution (TDR-004).
- **Unit:** `CalendarPalette.displayedHex(for:)` — the full 24-row table as a data-driven
  test, `"#"`-prefixed and bare input, upper and lower case, an unknown hex, an empty string,
  and a malformed value (each returned unchanged).
- **Guard:** assert the table has exactly 24 entries and no duplicate keys or values, so a
  transcription slip fails the suite rather than silently mispainting one color.

## Checklist
- [ ] `CalendarPalette` added, table transcribed from AYD-012
- [ ] Table values verified against Google Calendar's own rendering (step 2)
- [ ] Animator resolves through the palette; toggle/preset/contrast behavior unchanged
- [ ] Tests green, lint clean
- [ ] Changelog line
