---
id: SPEC-003
type: spec
status: draft
updated: 2026-07-11
parents: [AYD-001]
related: [GLO]
---

# SPEC-003: Scheduler + menu bar control

> Builds the **Scheduler** (precise per-Trigger timers, dedupe, sleep/wake) and the real
> **MenuBar UI / AppCoordinator** wiring that connects Poll → Scheduler → Overlay end to
> end (M3). Closes RF-04/RF-06, RNF-03/RNF-04.

## What (goal)
Arm a precise local timer for each new Trigger so the Overlay fires within <5 s of
`fireDate` (RNF-03), never firing the same Reminder twice (RN-03), surviving sleep/wake
(RNF-04); and drive the whole loop from a menu bar with status, on/off, test, reconnect,
quit (RF-06).

## Acceptance criteria
```gherkin
Scenario: Precise fire
  Given a Trigger with fireDate 30s from now
  When the Scheduler arms it
  Then the Overlay is enqueued within 5s of fireDate (RNF-03)

Scenario: Dedupe
  Given a Trigger id "evt1#10" already fired
  When poll() returns the same Trigger again
  Then it is not scheduled or fired again (RN-03)

Scenario: Sleep/wake re-sync
  Given Triggers were scheduled and the machine sleeps past some fireDates
  When the machine wakes
  Then the Scheduler re-polls and re-arms; only still-future, un-fired Triggers remain

Scenario: Toggle off
  Given the app is on with armed Triggers
  When the user clicks "Pause" in the menu
  Then no Triggers fire until turned back on; the status reflects paused

Scenario: Menu status
  Given the app is connected to Google
  When the user opens the menu
  Then it shows connection status and the count/next upcoming Trigger
```

## How (approach)
`Scheduler`: a `DispatchSourceTimer` per Trigger (or a single next-fire timer re-armed on
change); an in-memory `Set<String>` of fired ids for dedupe (RN-03); `onFire` →
`OverlayPresenter.enqueue`. A `~120s` poll timer (`CalendarService.poll`) feeds
`schedule([Trigger])`, which skips fired ids and re-arms changed ones. Subscribe to
`NSWorkspace.didWakeNotification` → force re-poll + re-arm (RNF-04).
`AppCoordinator` holds `AppState` (connected, enabled, nextTrigger) and wires
Auth+Calendar+Scheduler+Overlay. `MenuBarController` (`NSStatusItem`) renders status and
handles on/off, test, reconnect, quit.

## Steps
1. `Scheduler` — `schedule([Trigger])`, precise timer(s), `firedIds` dedupe, `onFire`, `enabled` gate, `cancelAll`.
2. Poll loop — repeating ~120s task calling `CalendarService.poll()` → `Scheduler.schedule`.
3. Sleep/wake — observe `NSWorkspace.didWakeNotification`; force re-poll + re-arm.
4. `AppState` + `AppCoordinator` — own the modules, expose actions (toggle, test, reconnect, quit).
5. `MenuBarController` — real menu: status line, Pause/Resume, Test animation, Reconnect Google, Quit; remove SPEC-001's temporary test wiring.

## Affected files
- `cal-reminder/Scheduler/Scheduler.swift`
- `cal-reminder/App/AppState.swift`
- `cal-reminder/App/AppCoordinator.swift`
- `cal-reminder/MenuBar/MenuBarController.swift`
- `cal-reminder/App/PollLoop.swift`
- `cal-reminderTests/SchedulerTests.swift`
- `cal-reminderTests/AppCoordinatorTests.swift`

## Tests
- **Acceptance:** precise-fire, dedupe, and toggle-off → `SchedulerTests` with an injected clock/timer and a spy Overlay (assert fire timing within tolerance, no double-fire, no fire while disabled). Sleep/wake re-sync → simulate the wake callback and assert re-poll + prune of past Triggers. Menu status → `AppCoordinatorTests` asserting `AppState` transitions; menu rendering verified **manually**.
- **Unit:** dedupe set add/skip; re-arm on changed fireDate; enabled gate blocks `onFire`.

## Checklist
- [ ] Fires within <5 s of fireDate (injected-clock test)
- [ ] Same id never fires twice
- [ ] Wake → re-poll + re-arm, past Triggers pruned
- [ ] Pause/Resume gates all firing
- [ ] Menu shows status + next Trigger; reconnect/quit work end to end
