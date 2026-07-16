---
id: SPEC-011
type: spec
status: draft
updated: 2026-07-16
parents: [AYD-001]
related: [GLO]
---

# SPEC-011: Click-to-skip toggle — what + how

> Makes the click-anywhere-to-skip behavior (RF-09) opt-out via a menu checkbox, and
> restores the old "airplane always finishes its trajectory" behavior when the box is
> unchecked. Refines RF-09 / RNF-02.

## What (goal)
Add a **"Click anywhere to skip"** checkbox to the `NSStatusItem` menu. When **checked**
(default), the Overlay keeps today's behavior: a click anywhere while a flight is playing
accelerates it to the end (~1.5s) and does not pass through. When **unchecked**, the Overlay
is fully click-through for the whole flight — clicks reach the windows below and the Airplane
completes its trajectory at the current Flight Speed. The choice persists across restarts and
applies from the next animation on.

## Acceptance criteria
```gherkin
Scenario: Skip enabled (default) — a click skips
  Given "Click anywhere to skip" is checked
  When a flight is playing and the user clicks anywhere on the screen
  Then the Airplane accelerates to cover the remaining distance in ~1.5s
  And the click does not reach the window below

Scenario: Skip disabled — the flight finishes and clicks pass through
  Given "Click anywhere to skip" is unchecked
  When a flight is playing and the user clicks anywhere on the screen
  Then the Airplane keeps flying to the end at the current Flight Speed
  And the click passes through to the window below

Scenario: Toggle from the menu
  Given the menu bar is open
  When the user clicks "Click anywhere to skip"
  Then the checkmark flips
  And the next flight uses the new behavior

Scenario: Persist across restarts
  Given the user previously unchecked "Click anywhere to skip"
  When the app relaunches
  Then "Click anywhere to skip" is unchecked
  And the next flight is click-through and finishes on its own

Scenario: Default
  Given the user never changed the setting
  When the app launches
  Then "Click anywhere to skip" is checked
```

## How (approach)
Mirror the `BannerColor` / `FlightSpeed` preference pattern. A `SkipOnClickStoring` protocol
wraps `UserDefaults` (default `true`) so it can be faked in tests. `DefaultOverlayAnimator`
reads the store per flight and sets `panel.ignoresMouseEvents = !skipOnClick`: when enabled it
keeps accepting clicks and wiring `onSkipRequested` (current behavior); when disabled the panel
stays click-through the whole flight (RNF-02 idle state), so the Airplane finishes on its own.
`StatusMenuController` renders a single checkmarked `NSMenuItem` whose action toggles the store
— a plain item (not the custom-view row Calendars needs), since one toggle per open is fine.

## Steps
1. `SkipOnClick.swift` — `SkipOnClickStoring` protocol + `UserDefaultsSkipOnClickStore` (key `"skipOnClick"`, default `true`).
2. `DefaultOverlayAnimator` — hold a `SkipOnClickStoring`; in `animate(text:)` set `panel.ignoresMouseEvents = !store.skipOnClick`, and only assign `view.onSkipRequested` when enabled.
3. `StatusMenuController` — add a "Click anywhere to skip" `NSMenuItem` with a checkmark reflecting the store; its action flips the store and the checkmark.
4. `AppDelegate` — own a `UserDefaultsSkipOnClickStore`, wire it into the animator and the menu controller.

## Affected files
- `cal-reminder/Overlay/SkipOnClick.swift`
- `cal-reminder/Overlay/OverlayPresenter.swift`
- `cal-reminder/MenuBar/StatusMenuController.swift`
- `cal-reminder/App/AppDelegate.swift`
- `cal-reminderTests/SkipOnClickStoreTests.swift`

## Tests
- **Acceptance:** persist-across-restarts and default scenarios → `SkipOnClickStoreTests` with an injected `UserDefaults` suite (no real defaults touched). The two click behaviors (skip vs pass-through-and-finish) and the menu checkmark are verified **manually**.
- **Unit:** store round-trips `true`/`false`; unset key falls back to `true`.

## Checklist
- [ ] "Click anywhere to skip" checkbox appears with a checkmark reflecting the current setting (manual)
- [ ] Checked: a click skips the flight and is not passed through (manual)
- [ ] Unchecked: a click passes through and the Airplane finishes its trajectory (manual)
- [ ] Selection persists across relaunch (`SkipOnClickStoreTests`)
- [ ] Default is `true` (checked) when unset (`SkipOnClickStoreTests`)
