---
id: SPEC-021
type: spec
status: draft
updated: 2026-09-10
parents: [AYD-011]
related: [GLO, REQ-01, SPEC-013, SPEC-017]
---

# SPEC-021: Event replica and Trigger lifecycle — what + how

> Implements AYD-011. `CalendarService` keeps a local replica of the Events in its window and
> derives Triggers from **the replica** on every Poll, so a Poll's return value is the complete
> desired set rather than whatever the last response happened to contain. The Scheduler stops
> merging-and-cancelling and starts reconciling against that set. Closes the three silent
> Reminder losses AYD-011 analyses: Events past the frozen sync window, the armed set wiped on
> sleep/wake and sign-out, and a Calendar wedged by a single deleted Event.

## What (goal)
Three coordinated changes, in dependency order — each is a shippable PR (§Slices):

1. **A deleted Event stops breaking a Poll.** `GoogleEvent.status` is read and `start` becomes
   optional, so a `cancelled` entry in a delta decodes instead of throwing and stranding that
   Calendar's `syncToken` forever.
2. **`CalendarService` holds an Event replica.** A full sync replaces a Calendar's replica; an
   incremental Poll upserts changed Events and removes cancelled ones; every Poll derives
   Triggers from the whole replica. The window grows to 48 h and the service forces a full sync
   whenever the last one is older than 6 h.
3. **The Scheduler reconciles.** `reconcile(_:authoritativeFor:)`, `rearmAll()` and
   `cancel(accountId:)` replace `schedule(_:)` and `cancelAll()`; `AppCoordinator` rewires
   every call site onto them.

> Refines **RNF-04**'s target: scheduled Triggers now survive sleep/wake as well as transient
> network failures. No change to RNF-06 — the Poll stays incremental at 5 minutes; the periodic
> full sync is what keeps the window moving.

## Acceptance criteria

```gherkin
# --- Slice 1: decode resilience -------------------------------------------------

Scenario: A cancelled Event in a delta does not break the Poll
  Given a previous Poll stored a syncToken for a Calendar
  And the next delta contains an entry with status "cancelled" and no start
  When the background Poll runs
  Then the Poll succeeds
  And the syncToken returned by that response is stored for the next Poll

# --- Slice 2: the replica -------------------------------------------------------

Scenario: An Event seen once keeps generating its Trigger on later Polls
  Given a full sync returned an Event inside the window
  When a later incremental Poll returns no Events at all
  Then that Event's Trigger is still present in the Poll's result

Scenario: A cancelled Event drops out of the replica
  Given a full sync returned an Event inside the window
  When an incremental Poll reports that Event as cancelled
  Then that Event's Trigger is absent from the Poll's result

Scenario: A changed Event replaces its previous version
  Given a full sync returned an Event starting at 14:00
  When an incremental Poll returns the same Event starting at 15:00
  Then the Poll's result carries the Trigger for 15:00
  And no Trigger for 14:00 remains

Scenario: The window advances without waiting for the user
  Given the last full sync happened more than the full-resync interval ago
  When the background Poll runs
  Then that Calendar is fetched without a syncToken over a fresh window
  And an Event that was beyond the previous window now generates its Trigger

Scenario: A Calendar whose fetch fails keeps its Triggers
  Given a full sync returned an Event for each of two Calendars
  When a later Poll fails for the first Calendar only
  Then the Poll's result still carries both Calendars' Triggers

Scenario: A deselected Calendar's Triggers disappear
  Given a full sync returned an Event for a selected Calendar
  When that Calendar is deselected and a Poll runs
  Then no Trigger for that Calendar is in the Poll's result

# --- Slice 3: the Trigger lifecycle ---------------------------------------------

Scenario: Waking re-arms the pending Triggers instead of dropping them
  Given a Trigger is armed for an upcoming Event
  When the Mac wakes from sleep
  Then that Trigger is still armed
  And its timer is recomputed against the current clock

Scenario: Reconciling cancels a Trigger whose Event is gone
  Given a Trigger is armed for an upcoming Event
  And the next Poll's result no longer contains it
  When the Poll completes
  Then that Trigger is no longer armed

Scenario: A failing Account does not disarm a healthy one
  Given each of two connected Accounts has an armed Trigger
  When a Poll succeeds for the first Account and fails for the second
  Then the first Account's Triggers are reconciled
  And the second Account's armed Trigger is untouched

Scenario: Signing out drops only that Account's Triggers
  Given each of two connected Accounts has an armed Trigger
  When the user signs one of them out
  Then only that Account's Trigger is cancelled

Scenario: Reconciling never replays an already-fired Reminder
  Given a Reminder already fired for an Event still inside the window
  When a later Poll returns that Event again
  Then that Reminder is not armed again
```

## How (approach)
- **Replica shape:** `[calendarId: [eventId: GoogleEvent]]` in `CalendarService`. The full-sync
  branch builds a fresh dictionary and assigns it **only after a successful fetch**, so a
  failure leaves the previous replica in place. The incremental branch mutates in place.
- **Staleness:** `CalendarService` keeps `lastFullSync: Date?` and treats a Poll as a full sync
  when `fullResync == true`, when there is no token for that Calendar, or when
  `now - lastFullSync >= fullResyncInterval`. The decision is per Poll, not per Calendar, so all
  selected Calendars share one window (`windowEnd`).
- **Derivation** moves out of the response loop into one pass over the replica, reusing the
  existing `ReminderResolver` call unchanged (RN-04/RN-06/RN-07 are untouched). Pruning
  (`start < now`, deselected Calendars) happens in the same pass.
- **Reconciliation:** the Scheduler keeps its `armed` dictionary and gains a set-difference —
  arm what is new, re-arm what moved, cancel what is in scope and absent, leave the rest alone.
  `rearmAll()` cancels each `Task` and re-arms from the retained `Armed.trigger`, so no Trigger
  data is lost across sleep/wake.

## Steps

### Slice 1 — decode resilience (PR 1)
1. `Models.swift`: add `status: String?` to `GoogleEvent`; make `start` optional
   (`EventDateTime?`).
2. `CalendarService.swift`: the derivation `guard` reads `event.start?.dateTime`; an Event with
   `status == "cancelled"` is skipped explicitly rather than falling through the parse guard.
3. `GoogleCalendarAPITests` / `CalendarServiceTests`: a delta containing a cancelled entry
   decodes, the Poll succeeds, and the response's `nextSyncToken` is stored.

### Slice 2 — the Event replica (PR 2)
4. `CalendarService.swift`: add `replica`, `windowEnd`, `lastFullSync`; raise `pollWindow` to
   48 h and add `fullResyncInterval` at 6 h.
5. Split `pollTriggers` into **fetch-and-apply** (full replace vs. delta upsert/remove) and
   **derive** (one pass over the replica → `[Trigger]`), with pruning of past Events and of
   replicas whose Calendar is no longer selected.
6. `poll(fullResync:)` decides full vs. incremental per §How, keeps the existing 410 retry, and
   returns the derived set. The `catch` per Calendar keeps skipping — the replica is what makes
   that non-destructive now.
7. `CalendarServiceTests`: the replica scenarios above.

### Slice 3 — the Trigger lifecycle (PR 3)
8. `Trigger.swift`: add the stored `accountId`, set at construction in `CalendarService`.
9. `Scheduler.swift`: replace `schedule(_:)` with `reconcile(_:authoritativeFor:)`; add
   `rearmAll()` and `cancel(accountId:)`; delete `cancelAll()`. Update `nextArmedTrigger()`'s
   doc comment — the armed set is now a reconciliation, not an accumulation.
10. `AccountRegistry.swift`: `poll` returns `authoritativeAccountIds: Set<String>` instead of
    `anyAccountSucceeded: Bool` (an Account is in the set when its `poll` returned without
    throwing).
11. `AppCoordinator.swift`: `poll(fullResync:)` reconciles with that scope and no longer
    cancels; `handleWake()` becomes `rearmAll()` + `poll()`; `signOut` uses
    `cancel(accountId:)`; `calendarsChanged()` / `remindersChanged()` / `refreshNow()` drop
    their `cancelAll()` and keep `poll(fullResync: true)`.
12. `docs/requirements.md`: refine RNF-04's target to state that Triggers survive sleep/wake.
13. `docs/architecture.md`: CalendarService's row gains the Event replica; Scheduler's row gains
    reconciliation.

## Affected files
- `cal-reminder/Calendar/Models.swift`
- `cal-reminder/Calendar/CalendarService.swift`
- `cal-reminder/Models/Trigger.swift`
- `cal-reminder/Scheduler/Scheduler.swift`
- `cal-reminder/Accounts/AccountRegistry.swift`
- `cal-reminder/App/AppCoordinator.swift`
- `cal-reminderTests/CalendarServiceTests.swift`
- `cal-reminderTests/GoogleCalendarAPITests.swift`
- `cal-reminderTests/SchedulerTests.swift`
- `cal-reminderTests/AccountRegistryTests.swift`
- `cal-reminderTests/AppCoordinatorTests.swift`
- `docs/requirements.md`
- `docs/architecture.md`

## Tests
- **Acceptance:** one test per Gherkin scenario above, in the slice's own PR.
  `CalendarServiceTests` drives the replica ones through the existing fake API (a scripted
  sequence of responses per Calendar, plus an injected clock to cross the 6 h resync
  threshold). `SchedulerTests` covers reconcile/rearm/scoped-cancel directly.
  `AppCoordinatorTests` covers the wiring, with the existing `FakeScheduler` gaining the three
  new methods.
- **Unit:** the `W ≥ R + M` boundary — an Event exactly at `windowEnd` and one just past it;
  `rearmAll()` dropping a past-due Trigger while keeping the rest; reconcile leaving an
  unchanged armed Trigger's `Task` alone (it must not re-arm and reset the timer).
- **Regression:** `test_wakeCancelsSchedulerBeforeRePolling` and
  `test_nextArmedTriggerIsNilAfterCancelAll` encode the behavior this SPEC removes — they are
  rewritten, not deleted, to assert the new contract. `test_nextTriggerSurvivesAPollWithNoChanges`
  must still pass, now for a structural reason rather than an accidental one.
- Dedupe (RN-03) is unchanged: `firedIds` is untouched by reconcile, rearm and scoped cancel.

## Slices (PRs)
| PR | Delivers | Independently shippable |
|----|----------|-------------------------|
| 1 | Steps 1–3 — a deleted Event no longer wedges a Calendar | Yes; fixes a live bug on its own |
| 2 | Steps 4–7 — the replica, the 48 h window, the 6 h resync | Yes; `schedule(_:)` stays additive and a complete set is still correct input for it |
| 3 | Steps 8–13 — `accountId`, reconciliation, the rewired call sites | Depends on PR 2 for the set to be authoritative |

## Checklist
- [ ] A `cancelled` entry in a delta decodes and the Poll stores the new `syncToken`
- [ ] An Event survives in the replica across Polls that do not mention it
- [ ] A cancelled Event leaves the replica; a changed one replaces its previous version
- [ ] A Poll escalates to a full sync once the last one is older than the resync interval
- [ ] A Calendar whose fetch fails keeps its Triggers; a deselected one loses them
- [ ] Waking re-arms pending Triggers against the current clock instead of dropping them
- [ ] Reconciliation cancels vanished Triggers and never touches an Account outside its scope
- [ ] Signing out cancels only that Account's Triggers
- [ ] An already-fired Reminder is never re-armed
