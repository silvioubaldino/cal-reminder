---
id: SPEC-013
type: spec
status: review
updated: 2026-08-14
parents: [AYD-001]
related: [SPEC-010, SPEC-012, GLO, REQ-01]
---

# SPEC-013: Manual refresh does a full resync — what + how

> Refines RF-12: the "Refresh now" control (SPEC-012) fires the *same incremental* Poll as the
> background loop, so it reuses the stored `syncToken` and only sees Events changed since the
> last sync. That makes it unable to do the one job it exists for — correcting a stale local
> state. A deleted or rescheduled Event leaves its armed Trigger behind (the delta reports it
> as `cancelled`, with no `start.dateTime`, and the parse step drops it silently), and no
> number of manual refreshes clears it. The manual Poll becomes a **full resync**: it discards
> the stored `syncToken`s, refetches the whole Poll window, and rebuilds the armed set from
> that result instead of merging into it.

## What (goal)
Two coordinated changes, both scoped to the manual path — the background Poll stays
incremental (RNF-06):
1. **`CalendarService` gains a full-resync Poll.** `poll(fullResync: true)` clears the stored
   per-Calendar `syncToken`s before fetching, so every selected Calendar goes back through the
   `timeMin`/`timeMax` branch and returns the complete window.
2. **`AppCoordinator.refreshNow()` rebuilds the armed set.** A full-resync Poll cancels every
   armed Trigger and re-arms from the returned list, so Triggers whose Event no longer exists
   in the window disappear. The cancel happens **after** the fetch succeeds, so a manual
   refresh that fails on the network leaves the current Triggers armed (RNF-04).

Already-fired Reminders are still deduped by `firedIds` (RN-03) — `cancelAll()` doesn't clear
it, so a full resync never replays a Reminder that already flew.

> Refines **RF-12**'s acceptance criterion: the manual Poll is a full resync, not an
> incremental one. No change to RNF-06 (the background Poll cadence and its `syncToken`
> use are untouched), and no change to the menu (SPEC-012's item and its "Refreshing…"
> state are reused as-is).

## Acceptance criteria
```gherkin
Scenario: Manual refresh refetches the whole window
  Given a previous Poll stored a syncToken for a Calendar
  When the user clicks "Refresh now"
  Then that Calendar is fetched without a syncToken
  And the next background Poll uses the syncToken returned by that fetch

Scenario: Background Poll stays incremental
  Given a previous Poll stored a syncToken for a Calendar
  When the background Poll runs
  Then that Calendar is fetched with the stored syncToken

Scenario: Manual refresh drops a Trigger whose Event is gone
  Given a Trigger is armed for an upcoming Event
  And that Event no longer exists in the Poll window
  When the user clicks "Refresh now"
  Then the armed set is rebuilt from the full resync
  And that Trigger is no longer armed

Scenario: A failed manual refresh keeps the armed Triggers
  Given a Trigger is armed for an upcoming Event
  When the user clicks "Refresh now" and the Poll fails with a network error
  Then the armed Triggers are NOT cancelled
  And the status stays connected

Scenario: A full resync does not replay an already-fired Reminder
  Given a Reminder already fired for an Event still inside the Poll window
  When the user clicks "Refresh now"
  Then that Reminder is not armed again
```

## How (approach)
- **`CalendarServicing`** replaces `poll()` with `poll(fullResync: Bool)`, plus a protocol
  extension `poll()` → `poll(fullResync: false)` so the background/wake/selection call sites
  stay untouched. `CalendarService.poll(fullResync:)` does `syncTokens.removeAll()` when the
  flag is set, before listing the Calendars. The cached `defaultReminders` are kept — they
  aren't sync state, and the full fetch refreshes them inline anyway (RN-04).
- **`AppCoordinator.poll(fullResync:)`** forwards the flag and, on success only, cancels the
  armed set before scheduling when `fullResync` is true. Failure paths are unchanged: an
  auth-fatal error still drops to `.needsReauth`, a network error still preserves the session
  *and* now also the armed Triggers.
- **`AppCoordinator.refreshNow()`** calls `poll(fullResync: true)`; the `guard !state.refreshing`
  and the `refreshing` flag lifecycle are unchanged.

## Steps
1. `CalendarService.swift`: change the `CalendarServicing.poll` requirement to
   `poll(fullResync:)`, add the `poll()` convenience extension, and clear `syncTokens` in the
   implementation when `fullResync` is true.
2. `AppCoordinator.swift`: add the `fullResync` parameter to `poll(_:)` (default `false`),
   forward it to `calendar.poll(fullResync:)`, and `await scheduler.cancelAll()` after a
   successful full-resync fetch and before `schedule(_:)`; `refreshNow()` passes `true`.
3. `docs/requirements.md`: refine RF-12's acceptance criterion to state that the manual Poll
   is a full resync.

## Affected files
- `cal-reminder/Calendar/CalendarService.swift`
- `cal-reminder/App/AppCoordinator.swift`
- `cal-reminderTests/CalendarServiceTests.swift`
- `cal-reminderTests/AppCoordinatorTests.swift`
- `docs/requirements.md`

## Tests
- **Acceptance:** `CalendarServiceTests` — a full-resync Poll after a token-storing Poll sends
  `nil` as the `syncToken` and re-stores the token returned by that fetch; a plain Poll still
  sends the stored token. `AppCoordinatorTests` — `refreshNow()` cancels the scheduler and
  re-arms from the returned list, so a Trigger absent from the resync is gone; a full resync
  whose fetch throws does **not** cancel; the fake `CalendarServicing` records the `fullResync`
  flag per call, asserting `refreshNow()` sets it and `poll()`/`handleWake()` don't.
- **Unit:** `refreshNow()`'s existing `refreshing` transitions still hold (SPEC-012).

## Checklist
> Implemented; the boxes stay open until the suite runs — the change was written in an
> environment without an Xcode/Swift toolchain, so the CI gate (RNF-09) is what verifies it.

- [ ] Manual refresh fetches every selected Calendar without a `syncToken`
- [ ] Background Poll still fetches with the stored `syncToken`
- [ ] Manual refresh rebuilds the armed set, dropping Triggers whose Event is gone
- [ ] A failed manual refresh leaves the armed Triggers intact
- [ ] An already-fired Reminder is not re-armed by a full resync
