---
id: SPEC-012
type: spec
status: done
updated: 2026-07-31
parents: [AYD-001]
related: [SPEC-010, GLO, REQ-01]
---

# SPEC-012: Always-on manual refresh — what + how

> Revises RF-12: the manual-refresh control introduced by SPEC-010 was only clickable
> when there was no upcoming Trigger, which left no way to force a resync when the
> cached state (and its upcoming Trigger) had simply gone stale between background
> Polls. Replaces that empty-state-only row with a dedicated "Refresh now" menu item
> that is always available, so a stale sync can always be corrected manually.

## What (goal)
A separate **"Refresh now"** `NSStatusItem` menu item, always present and always clickable,
independent of whether a Trigger is currently upcoming. It fires the same manual Poll as
before (`AppCoordinator.refreshNow()`); its only disabled state is while that Poll it
triggered is actually running. The next-Trigger row goes back to being a plain, non-clickable
status label in every state.

## Acceptance criteria
```gherkin
Scenario: Refresh is clickable with no upcoming Trigger
  Given the status is connected
  And there is no upcoming Trigger
  When the user clicks "Refresh now"
  Then a manual Poll runs
  And the item reads "Refreshing…" and is disabled while it runs

Scenario: Refresh is clickable even with an upcoming Trigger
  Given the status is connected
  And there is an upcoming Trigger
  When the user clicks "Refresh now"
  Then a manual Poll runs, the same as with no upcoming Trigger

Scenario: Refresh disables only while its own Poll is in flight
  Given a manual Poll triggered by "Refresh now" is running
  When the menu renders
  Then "Refresh now" reads "Refreshing…" and is disabled
  And once the Poll completes it reverts to "Refresh now" and is enabled again

Scenario: Next-Trigger row stays a plain label
  When the menu renders, regardless of connection or refresh state
  Then the next-Trigger row shows "Next: <title> <time>" or "No upcoming reminders"
  And it is never clickable
```

## How (approach)
`StatusMenuController` adds a standalone `refreshItem` `NSMenuItem` (arrow.clockwise icon,
`#selector(handleRefresh)` → the existing `onRefresh` closure → `AppCoordinator.refreshNow()`,
unchanged) placed right after the next-Trigger row. `render(_:)` drives only its title/
`isEnabled` from `state.refreshing`; the next-Trigger row's `action`/`target`/`image`/
`isEnabled` branching from SPEC-010 is removed — it always renders as a disabled label.
`AppCoordinator.refreshNow()`'s existing `guard !state.refreshing` keeps a concurrent click
a no-op, matching the item's own disabled state. No changes to `AppState`/`AppCoordinator`.

## Steps
1. `StatusMenuController.swift`: add `refreshItem`; wire it in `buildMenu()`; simplify
   `nextTriggerLabel`'s `render(_:)` branch to a plain title switch; drive `refreshItem.title`/
   `isEnabled` from `state.refreshing` only.

## Affected files
- `cal-reminder/MenuBar/StatusMenuController.swift`

## Tests
- **Acceptance:** covered by existing `AppCoordinatorTests` for `refreshNow()`'s
  `state.refreshing` transitions (unchanged by this SPEC). The menu item's always-enabled
  behavior and title swap are verified **manually** (no `StatusMenuController` unit tests
  exist in this project — it's exercised via `AppDelegate` wiring and manual menu inspection).

## Checklist
- [x] "Refresh now" is clickable with no upcoming Trigger
- [x] "Refresh now" is clickable with an upcoming Trigger
- [x] "Refresh now" reads "Refreshing…" and disables only while its own Poll runs
- [x] Next-Trigger row is a plain, never-clickable label in every state
