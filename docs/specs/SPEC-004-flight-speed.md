---
id: SPEC-004
type: spec
status: draft
updated: 2026-07-11
parents: [AYD-001]
related: [GLO]
---

# SPEC-004: Flight Speed menu

> Lets the user pick how fast the Airplane crosses the Overlay, from 3 presets in the
> menu bar. Closes RF-06/RF-07.

## What (goal)
Add a "Flight Speed" submenu with 3 presets (Slow/Normal/Fast) to the `NSStatusItem`
menu; the selection persists across restarts and is used by the next animation played.

## Acceptance criteria
```gherkin
Scenario: Pick a preset
  Given the menu bar is open
  When the user selects "Fast" under "Flight Speed"
  Then a checkmark moves to "Fast"
  And the next Overlay animation flies at the Fast duration

Scenario: Persist across restarts
  Given the user previously selected "Slow"
  When the app relaunches
  Then "Flight Speed" shows "Slow" checked
  And the next animation flies at the Slow duration

Scenario: Default
  Given no Flight Speed was ever chosen
  When the app launches
  Then "Normal" is checked and used
```

## How (approach)
A `FlightSpeed` enum (`slow`, `normal`, `fast`) maps each preset to a flight duration.
A small `FlightSpeedStore` protocol wraps `UserDefaults` (the persistence boundary) so
it can be faked in tests. `DefaultOverlayAnimator` reads the store's current value at
`animate(text:)` time and passes the duration into `AirplaneBannerView.animate(text:duration:)`,
replacing the previous hardcoded constant. `StatusMenuController` renders a submenu of
3 `NSMenuItem`s with a checkmark on the current preset; selecting one writes to the
store and moves the checkmark.

## Steps
1. `FlightSpeed` enum — cases + `displayName` + `flightDuration`.
2. `FlightSpeedStore` protocol + `UserDefaultsFlightSpeedStore` (default `.normal`).
3. `AirplaneBannerView.animate(text:duration:)` — drop the static `flightDuration` constant, take duration as a parameter.
4. `DefaultOverlayAnimator` — hold a `FlightSpeedStore`, read it before each `animate` call.
5. `StatusMenuController` — "Flight Speed" submenu (3 items, checkmark, target/action), `onSelectSpeed` callback.
6. `AppDelegate` — own the `UserDefaultsFlightSpeedStore`, wire it into the animator and the menu controller.

## Affected files
- `cal-reminder/Overlay/FlightSpeed.swift`
- `cal-reminder/Overlay/AirplaneBannerView.swift`
- `cal-reminder/Overlay/OverlayPresenter.swift`
- `cal-reminder/MenuBar/StatusMenuController.swift`
- `cal-reminder/App/AppDelegate.swift`
- `cal-reminderTests/FlightSpeedStoreTests.swift`

## Tests
- **Acceptance:** persist-across-restarts and default scenarios → `FlightSpeedStoreTests` with an injected `UserDefaults` suite (no real defaults touched). Menu checkmark and visual flight-speed change are verified **manually**.
- **Unit:** `FlightSpeed.flightDuration` ordering (`slow > normal > fast`); store round-trips each case; unset key falls back to `.normal`.

## Checklist
- [ ] "Flight Speed" submenu shows 3 presets with a checkmark on the current one (manual)
- [ ] Selecting a preset changes the next animation's speed (manual)
- [x] Selection persists across relaunch (`FlightSpeedStoreTests`)
- [x] Default is `.normal` when unset (`FlightSpeedStoreTests`)
