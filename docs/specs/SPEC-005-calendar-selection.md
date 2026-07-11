---
id: SPEC-005
type: spec
status: draft
parents: [AYD-002]
related: [GLO]
updated: 2026-07-11
---

# SPEC-005: Calendar selection — what + how

> Reads every Calendar in the connected account and lets the user pick, from the menu bar,
> which ones generate Triggers. Closes RF-10 (and the RF-06 menu addition). Implements
> AYD-002; doesn't redefine it.

## What (goal)
List the account's Calendars in a "Calendars" submenu with a checkbox each (multi-select);
only checked Calendars are Polled into Triggers; the selection persists across restarts and
a change re-Polls immediately. Default when never chosen: **all Calendars**.

## Acceptance criteria
```gherkin
Scenario: Default is all Calendars
  Given the user has never chosen Calendars
  And the account has Calendars A and B
  When a Poll runs
  Then events.list is called for both A and B
  And Triggers from both are returned

Scenario: Only selected Calendars are Polled
  Given the selection is {A}
  And the account has Calendars A and B
  When a Poll runs
  Then events.list is called only for A
  And only A's Triggers are returned

Scenario: Deselect keeps the others
  Given all Calendars are effectively selected (never chosen)
  And the account has A, B, C
  When the user unchecks B in the menu
  Then the stored selection becomes {A, C}

Scenario: Persist across restarts
  Given the user previously selected {A}
  When the app relaunches
  Then the "Calendars" submenu shows only A checked
  And the next Poll targets only A

Scenario: Dedupe is per Calendar
  Given Calendars A and B each hold an Event with the same id and a 10-min popup Reminder
  When a Poll runs
  Then two distinct Triggers are produced (ids "A#<eventId>#10" and "B#<eventId>#10")

Scenario: Selection change re-Polls
  Given the app is connected
  When the user toggles a Calendar in the menu
  Then the Scheduler is re-armed from a fresh Poll (no wait for the ~120s timer)
```

## How (approach)
`GoogleCalendarAPI` gains `listCalendars()` (`calendarList.list`, keeping `accessRole` in
owner/writer/reader) and `listEvents` takes a `calendarId` (URL-encoded path). `CalendarService`
holds a `CalendarSelectionStoring`, lists Calendars each Poll, resolves the effective set
(`stored ?? allIds`, intersected with `allIds` to drop stale ids), and loops `events.list` per
selected Calendar with **per-`calendarId`** `syncToken`/`defaultReminders` dictionaries; Trigger
dedupe ids gain a `calendarId#` prefix. The store is a thin `UserDefaults` boundary holding an
optional `Set<String>` (nil = never chosen). The menu-facing domain type is `CalendarInfo`
(named so to avoid colliding with `Foundation.Calendar`). `AppCoordinator.poll()` also fills
`state.calendars` via `availableCalendars()`; `StatusMenuController.render(_:)` rebuilds the
"Calendars" submenu from `state.calendars` + the selection store; toggling writes the
materialized set and calls `onCalendarsChanged` → `AppCoordinator` cancels all timers and
re-Polls (same pattern as `handleWake`).

## Steps
1. **Models** (`Models.swift`): add `GoogleCalendarListEntry {id, summary, primary?, accessRole}`,
   `GoogleCalendarListResponse {items}`, and domain `CalendarInfo {id, title, isPrimary}`.
2. **CalendarSelectionStore** (new file): `CalendarSelectionStoring` protocol
   (`var selectedCalendarIds: Set<String>? { get set }`) + `UserDefaultsCalendarSelectionStore`
   (persist as `[String]?` under key `selectedCalendarIds`; nil when the key is absent).
3. **GoogleCalendarAPI**: add `listCalendars() async throws -> [GoogleCalendarListEntry]`
   (filter `accessRole ∈ {owner, writer, reader}`); change `listEvents` to take `calendarId`
   and build the path `calendars/{calendarId}/events` (URL-encoded). Keep the inline
   `defaultReminders` in the return tuple.
4. **CalendarService**: inject `CalendarSelectionStoring`; replace the single `syncToken`/
   `cachedDefaultReminders` with `[calendarId: String]` / `[calendarId: [GoogleCalendarDefaultReminder]]`.
   `poll()` → `listCalendars()` → effective set (`stored?.intersection(allIds) ?? allIds`) →
   per-Calendar `events.list` → Triggers with id `"\(calendarId)#\(event.id)#\(minutes)"`.
   Add `availableCalendars() async throws -> [CalendarInfo]` to `CalendarServicing`.
   On `unexpectedStatus(410)` for a Calendar (expired `syncToken`), drop that id's token and
   retry that Calendar once without a token.
5. **AppState**: add `var calendars: [CalendarInfo] = []`.
6. **AppCoordinator**: in `poll()`, set `state.calendars = (try? await calendar.availableCalendars()) ?? state.calendars`;
   add `calendarsChanged()` → `Task { await scheduler.cancelAll(); await poll() }`.
7. **StatusMenuController**: hold a `CalendarSelectionStoring` + `onCalendarsChanged`; add a
   "Calendars" submenu item; in `render(_:)` rebuild it from `state.calendars` (checkbox per
   Calendar, checked = effective-selected; disabled placeholder when empty/not connected).
   Toggling materializes `stored ?? allIds`, applies the change, saves, flips the checkmark,
   and calls `onCalendarsChanged`.
8. **AppDelegate**: own `UserDefaultsCalendarSelectionStore`; pass it to `CalendarService` and
   `StatusMenuController`; wire `onCalendarsChanged` → `coordinator.calendarsChanged()`.

## Affected files
- `cal-reminder/Calendar/Models.swift`
- `cal-reminder/Calendar/CalendarSelectionStore.swift` *(new)*
- `cal-reminder/Calendar/GoogleCalendarAPI.swift`
- `cal-reminder/Calendar/CalendarService.swift`
- `cal-reminder/App/AppState.swift`
- `cal-reminder/App/AppCoordinator.swift`
- `cal-reminder/MenuBar/StatusMenuController.swift`
- `cal-reminder/App/AppDelegate.swift`
- `cal-reminderTests/CalendarSelectionStoreTests.swift` *(new)*
- `cal-reminderTests/CalendarServiceTests.swift`

## Tests
- **Acceptance:**
  - Default-all, only-selected, and per-Calendar-dedupe scenarios → `CalendarServiceTests` with a
    fake `GoogleCalendarAPIProtocol` (records which `calendarId`s were requested) and a fake
    selection store.
  - Deselect-keeps-others and persist-across-restarts → `CalendarSelectionStoreTests` with an
    injected `UserDefaults` suite (materialize-on-toggle logic + round-trip; unset key → nil).
  - Menu checkboxes and the immediate re-Poll on toggle are verified **manually**.
- **Unit:** effective-set resolution (`nil → all`, stale id intersected out); per-`calendarId`
  `syncToken` isolation (token for A not sent to B); `410` on one Calendar drops only its token
  and retries once; `accessRole` filter drops `freeBusyReader`.

## Checklist
- [ ] "Calendars" submenu lists every Calendar with a checkmark on the selected ones (manual)
- [ ] Toggling a Calendar re-Polls immediately and updates upcoming Triggers (manual)
- [ ] Default with no stored choice Polls all Calendars (`CalendarServiceTests`)
- [ ] Only selected Calendars are Polled (`CalendarServiceTests`)
- [ ] Dedupe ids are prefixed with `calendarId` (`CalendarServiceTests`)
- [ ] Deselect keeps the other Calendars; selection persists across relaunch (`CalendarSelectionStoreTests`)
