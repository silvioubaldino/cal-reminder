---
id: SPEC-017
type: spec
status: done
parents: [AYD-008]
related: [GLO, REQ-01, AYD-001, SPEC-006, SPEC-013]
updated: 2026-09-04
---

# SPEC-017: Reminder selection menu — what + how

> Implements AYD-008 (RF-15, RN-07): a "Reminders" submenu where the user switches the Event's
> own Reminders on/off and checks any number of Extra Reminders (at start, 1, 5, 10, 15 minutes
> before). The effective Reminders of every Event become the union of both, the selection
> persists, and changing it rebuilds the upcoming Triggers immediately.

## What (goal)
1. A new `ReminderSettings` value (inherit flag + chosen Extra Reminder minutes), persisted
   app-wide, defaulting to today's behavior (inherit on, no extras).
2. `ReminderResolver` returns the **union** of the inherited branch and the Extra Reminders.
3. A "Reminders" submenu in the menu bar that states its own selection in its title and warns
   when the selection is empty.
4. Changing the selection cancels the armed Triggers and re-Polls as a **full resync**.
5. A Trigger at 0 minutes reads "starting now" on the Banner.

## Acceptance criteria
```gherkin
Scenario: Default settings behave exactly like today
  Given the user has never opened the Reminders menu
  When an Event with a 10-minute popup Reminder is resolved
  Then the resolved minutes are exactly [10]

Scenario: An Extra Reminder is added on top of the Event's own
  Given "Event's own reminders" is on and "1 minute before" is checked
  When an Event with a 10-minute popup Reminder is resolved
  Then the resolved minutes are exactly [10, 1]

Scenario: The RN-06 fallback still applies under an Extra Reminder
  Given "Event's own reminders" is on and "1 minute before" is checked
  When an Event with no popup Reminder is resolved
  Then the resolved minutes are exactly [5, 1]

Scenario: An Extra Reminder that duplicates the Event's own fires once
  Given "Event's own reminders" is on and "5 minutes before" is checked
  When an Event with a 5-minute popup Reminder is resolved
  Then the resolved minutes are exactly [5]

Scenario: Extra Reminders only, ignoring the calendar
  Given "Event's own reminders" is off and "1 minute before" and "15 minutes before" are checked
  When an Event with a 30-minute popup Reminder is resolved
  Then the resolved minutes are exactly [1, 15]

Scenario: Nothing selected means no Trigger at all
  Given "Event's own reminders" is off and no Extra Reminder is checked
  When an Event with a 10-minute popup Reminder is resolved
  Then no minutes are resolved
  And the Event generates no Trigger

Scenario: The selection persists across restarts
  Given the user checked "1 minute before" and turned "Event's own reminders" off
  When the app is restarted
  Then the Reminders menu still shows exactly that selection

Scenario: The menu states the current selection without being opened
  Given "Event's own reminders" is on and "1 minute before" and "5 minutes before" are checked
  Then the Reminders menu item reads "Reminders (calendar + 1, 5 min)"

Scenario: The empty selection is visible and warned about
  Given "Event's own reminders" is off and no Extra Reminder is checked
  Then the Reminders menu item reads "Reminders (none)"
  And the submenu shows a disabled warning row that no Event will be announced

Scenario: Changing the selection rebuilds the upcoming Triggers immediately
  Given Triggers are armed from an earlier Poll
  When the user checks "1 minute before"
  Then the armed Triggers are cancelled
  And a full resync Poll runs (sync tokens dropped), without waiting for the next background Poll

Scenario: A Reminder at start time reads "starting now"
  Given a Trigger with 0 minutes before an Event starting at 14:00
  When the Banner text is formatted
  Then it reads "<Title>\nat 14:00 (starting now)"
```

## How (approach)
`ReminderSettings` is a pure value type carrying the presets, their labels and the summary
string, so both the resolver and the menu read from one source and both are testable without
AppKit or `UserDefaults`. `UserDefaultsReminderSettingsStore` follows the existing
`SkipOnClickStoring` shape (protocol + `UserDefaults`-backed implementation, faked in tests).

`ReminderResolver.popupReminderMinutes` gains a `settings` parameter defaulted to
`.default`, so every existing call site and test keeps today's meaning. The inherited branch is
the current implementation untouched (RN-04 + RN-06 fallback), gated by the flag; the extras are
appended in ascending order, minus any minute the inherited branch already produced (RN-07).

`CalendarService` takes a `ReminderSettingsStoring` and reads it **per Poll** (not at init), so
a selection change is picked up by the very next Poll. `StatusMenuController` builds the
submenu, retitles the parent item on every toggle, and calls `onRemindersChanged`, wired in
`AppDelegate` to `AppCoordinator.remindersChanged()` → `cancelAll()` + `poll(fullResync: true)`
(full resync per AYD-008: an incremental Poll would return no Events and lose the Triggers).

## Steps
1. `cal-reminder/Calendar/ReminderSettings.swift` (new): `ReminderSettings` value type
   (`inheritEventReminders`, `extraMinutes`, `presetMinutes`, `label(forMinutes:)`, `isSilent`,
   `summary`, `menuTitle`) + `ReminderSettingsStoring` + `UserDefaultsReminderSettingsStore`.
2. `ReminderResolver.swift`: add the `settings:` parameter and apply RN-07.
3. `CalendarService.swift`: inject `reminderSettingsStore`, read it per Poll, pass it to the
   resolver, and skip Events that resolve to no minutes.
4. `StatusMenuController.swift`: `remindersMenuItem()` + `refreshRemindersMenu()` (checkmarks,
   parent title, warning row), `onRemindersChanged` callback, `reminderSettingsStore` injection.
5. `AppCoordinator.swift`: `remindersChanged()` — `cancelAll()` then `poll(fullResync: true)`.
6. `AppDelegate.swift`: own a `UserDefaultsReminderSettingsStore`, pass it to both the menu and
   `CalendarService`, wire `onRemindersChanged`.
7. `BannerText.swift`: `minutesBefore == 0` → `(starting now)`.

## Affected files
- `cal-reminder/Calendar/ReminderSettings.swift` (new)
- `cal-reminder/Calendar/ReminderResolver.swift`
- `cal-reminder/Calendar/CalendarService.swift`
- `cal-reminder/MenuBar/StatusMenuController.swift`
- `cal-reminder/App/AppCoordinator.swift`
- `cal-reminder/App/AppDelegate.swift`
- `cal-reminder/Overlay/BannerText.swift`
- `cal-reminderTests/ReminderSettingsTests.swift` (new)
- `cal-reminderTests/StatusMenuControllerTests.swift` (new)
- `cal-reminderTests/ReminderResolverTests.swift`
- `cal-reminderTests/CalendarServiceTests.swift`
- `cal-reminderTests/AppCoordinatorTests.swift`
- `cal-reminderTests/BannerTextTests.swift`

## Tests
- **Acceptance:** one case per Gherkin scenario — resolution scenarios in
  `ReminderResolverTests` (pure, hand-built `GoogleEvent` + defaults + settings), persistence in
  `ReminderSettingsTests` against a scratch `UserDefaults` suite, the menu title/warning and
  checkmark state in `StatusMenuControllerTests`, the immediate full-resync rebuild in
  `AppCoordinatorTests` (spy Scheduler + stub accounts asserting `cancelAll` then
  `poll(fullResync: true)`), and the Banner copy in `BannerTextTests`.
- **Unit:** `summary`/`menuTitle` for each shape (inherit only, extras only, both, none);
  `label(forMinutes:)` for 0/1/n; `isSilent`; `CalendarServiceTests` — an Event resolving to no
  minutes produces no Trigger, and extras produce one Trigger per minute with distinct ids
  (RN-03).

## Checklist
- [x] Default settings resolve exactly like today (`ReminderResolverTests`)
- [x] Extra Reminder is unioned on top of the Event's own, deduped (`ReminderResolverTests`)
- [x] RN-06 fallback still applies alongside an Extra Reminder (`ReminderResolverTests`)
- [x] Inherit off → only the Extra Reminders (`ReminderResolverTests`)
- [x] Empty selection → no minutes, no Trigger (`ReminderResolverTests`, `CalendarServiceTests`)
- [x] Selection persists across restarts (`ReminderSettingsTests`)
- [x] Menu title states the selection; empty selection warns (`StatusMenuControllerTests`)
- [x] Toggling a Reminder cancels armed Triggers and full-resyncs (`AppCoordinatorTests`)
- [x] 0 minutes reads "starting now" (`BannerTextTests`)
