---
id: SPEC-001
type: spec
status: review
updated: 2026-07-31
parents: [AYD-001]
related: [GLO]
---

# SPEC-001: Overlay — airplane + banner animation

> Builds the **OverlayPresenter**: a click-through, above-everything window that flies
> the Airplane pulling the Banner across the main screen, with a FIFO queue. Fully
> testable via a "Test animation" menu action — no Google needed (M1).

## What (goal)
At `enqueue(Trigger)`, slide an Airplane pulling a Banner reading `<Title> at HH:MM (in X min)`
across `NSScreen.main`, over all windows (including fullscreen), without stealing focus or
blocking clicks; overlapping requests play one at a time (RN-05).

## Acceptance criteria
```gherkin
Scenario: Fly the airplane over all windows
  Given the app is running and a fullscreen app is in front
  When a Trigger is enqueued
  Then an airplane pulling a banner slides across the main screen above that app
  And clicks during the animation reach the window below (Overlay is click-through)
  And the menu bar / other apps keep focus (Overlay never becomes key)

Scenario: Banner text
  Given a Trigger with title "Standup", start 14:00, 5 minutes before
  When it is enqueued
  Then the banner reads "Standup" bold on the first line and "at 14:00 (in 5 min)" italic
    on the second
  And both lines are centered within the Banner

Scenario: One animation at a time (FIFO)
  Given an animation is currently playing
  When a second Trigger is enqueued
  Then it waits and starts only after the first finishes, in arrival order

Scenario: Test action
  Given the menu bar is open
  When the user clicks "Test animation"
  Then a sample airplane + banner animation plays

Scenario: Long title widens the Banner instead of overflowing
  Given a Trigger whose title doesn't fit the Banner's base width
  When it is enqueued
  Then the Banner grows wider (up to its maximum) to fit the title instead of clipping it
  And beyond that maximum the text wraps (up to 3 lines) and only then truncates
```

## How (approach)
`NSPanel` (borderless, non-activating) with `level = .screenSaver`,
`collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`,
`ignoresMouseEvents = true`, clear background, `hidesOnDeactivate = false`. Content is a
Core Animation layer: an Airplane view + Banner view whose position animates left→right
across the screen width. A serial in-memory queue drains one Trigger at a time; each
animation resolves a completion that dequeues the next. Banner text via a pure formatter
`bannerText(title:start:minutesBefore:) -> String`.

The Banner text is formatted on two lines — the title, then `at HH:MM (in X min)` — so the
split is deliberate rather than left to automatic wrapping. `AirplaneBannerView` renders it as
an `NSAttributedString` (title bold, time italic, both centered) instead of a plain
`CATextLayer` string. Before each flight the Banner is measured from that styled text: it keeps
a fixed base width and grows wider on demand (up to a maximum) for a long title; only past that
maximum does the text wrap (`CATextLayer.isWrapped`, up to 3 lines) and then truncate with an
ellipsis. The text block is centered vertically in the Banner, and the Airplane and rope stay
centered against it. The real group width is passed to `FlightSpeed`, so a widened Banner still
flies at the same points per second.

## Steps
1. `OverlayPanel: NSPanel` subclass — window flags, `canBecomeKey=false`, full-screen frame of `NSScreen.main`.
2. `AirplaneBannerView` (Core Animation): airplane sprite + banner strip; expose `animate(text:) async` that runs the cross-screen slide and returns on completion.
3. `bannerText(title:start:minutesBefore:)` — pure, `HH:MM` + `(in X min)`; unit-testable.
4. `OverlayPresenter`: `enqueue(_ Trigger)`; serial `AsyncStream`/actor queue; show panel → animate → hide → next.
5. Wire a temporary "Test animation" item into the `NSStatusItem` menu that enqueues a sample Trigger.

## Affected files
- `cal-reminder/Overlay/OverlayPanel.swift`
- `cal-reminder/Overlay/AirplaneBannerView.swift`
- `cal-reminder/Overlay/OverlayPresenter.swift`
- `cal-reminder/Overlay/BannerText.swift`
- `cal-reminderTests/BannerTextTests.swift`
- `cal-reminderTests/OverlayQueueTests.swift`

## Tests
- **Acceptance:** banner-text scenario → `BannerTextTests`; FIFO scenario → `OverlayQueueTests` (enqueue 2, assert order + non-overlap via a stubbed animator/clock). Over-all-windows and click-through are verified **manually** (window flags can't be unit-asserted meaningfully).
- **Unit:** `bannerText` formatting (padding, minute rounding, edge `in 0 min`); queue actor keeps FIFO under concurrent enqueue.

## Checklist
- [ ] Panel appears over a fullscreen app on all Spaces (manual)
- [ ] Clicks pass through; Overlay never becomes key (manual)
- [x] Banner text matches RF-05 format (`BannerTextTests`)
- [x] FIFO queue: no two animations overlap (`OverlayQueueTests`)
- [ ] "Test animation" menu item plays a sample (manual — app launches and the menu action is wired; visual confirmation pending)
- [ ] A long title widens the Banner instead of overflowing; both lines stay centered (manual)
