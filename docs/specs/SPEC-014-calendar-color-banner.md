---
id: SPEC-014
type: spec
status: done
updated: 2026-08-14
parents: [AYD-006]
related: [GLO, REQ-01, SPEC-005, TDR-004]
---

# SPEC-014: Banner painted with the Calendar Color — what + how

> Implements AYD-006 / RF-13: carry each Calendar's own color from the Poll to the Banner, so
> a Reminder is recognizable by color alone, behind a "Match calendar color" toggle that
> falls back to the existing color preset (RF-08).

## What (goal)
The Calendar Color already arrives on the `calendarList.list` response the Poll makes; it is
decoded, stamped on each Trigger, and applied by the animator at fire time. When the toggle is
off — or the Calendar has no color, or the flight is the test animation — the Banner keeps
using the selected preset, exactly as today.

## Acceptance criteria
1. `GoogleCalendarListEntry` decodes `backgroundColor`, and a response without that key still
   decodes (no Calendar Color → `nil`).
2. Every Trigger built by `CalendarService.poll` carries the `backgroundColor` of the Calendar
   it came from, and `nil` when that Calendar has none.
3. `OverlayPresenter` passes the Trigger's `calendarColorHex` to the animator alongside the
   Banner text, preserving the FIFO order (RN-05).
4. With "Match calendar color" **on**, the animator paints the Banner with the parsed Calendar
   Color; with it **off**, or when the hex is absent/unparseable, it paints the selected preset.
5. The Banner's text color is derived from the background's luminance: white on a dark Banner,
   near-black on a light one.
6. `UserDefaultsMatchCalendarColorStore` defaults to `true` when unset and round-trips both
   values across store instances sharing the same `UserDefaults`.
7. The "Banner Color" submenu shows "Match calendar color" as its first item, checked from the
   store, with a separator before the presets; toggling it flips the checkmark and persists.
8. The test animation (RF-06) carries no Calendar Color and therefore uses the preset.

## How (steps)
1. **Models** — add `backgroundColor: String?` to `GoogleCalendarListEntry`;
   add `calendarColorHex: String?` to `Trigger` (default `nil`, so existing construction sites
   and tests stay valid).
2. **CalendarService** — build `colorsById` from the `listCalendars()` result `poll` already
   fetches, and pass the Calendar's color into `pollTriggers` so each Trigger is stamped.
3. **BannerColor.swift** — add `NSColor(bannerHex:)` (parses `#RRGGBB` / `RRGGBB`),
   `NSColor.readableBannerTextColor` (luminance rule), and the
   `MatchCalendarColorStoring` / `UserDefaultsMatchCalendarColorStore` pair (default `true`).
4. **OverlayAnimating** — widen to `animate(text:calendarColorHex:)`;
   `DefaultOverlayAnimator` resolves background + text color; `OverlayPresenter` forwards the
   Trigger's color.
5. **AirplaneBannerView** — hold a `bannerTextColor` (default white) used by
   `attributedBannerText`, set via `setBannerTextColor`.
6. **StatusMenuController** — "Match calendar color" item + separator at the top of the
   "Banner Color" submenu, wired to the new store.

## Tests
| Criterion | Test |
|-----------|------|
| 1 | `GoogleCalendarAPITests`: `calendarList` fixture with and without `backgroundColor` |
| 2 | `CalendarServiceTests`: Triggers from two Calendars carry each one's color; a colorless Calendar yields `nil` |
| 3 | `OverlayQueueTests`: the spy animator records the color it received, in order |
| 4, 5 | `BannerColorStoreTests`: hex parsing, preset fallback, and the readable-text rule |
| 6 | `BannerColorStoreTests`: default `true` + round-trip |

## Out of scope
Per-Event colors (`event.colorId`), custom color pickers, and coloring the Airplane/rope.
