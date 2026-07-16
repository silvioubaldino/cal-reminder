---
id: SPEC-006
type: spec
status: draft
parents: [AYD-001]
related: [GLO, REQ-01]
updated: 2026-07-16
---

# SPEC-006: Default popup Reminder for Events without one — what + how

> When an Event resolves to **no** popup Reminder (RN-04), the app synthesizes a single
> 5-minutes-before Reminder so it still gets an Overlay. When the Event already has any popup
> Reminder, only the existing ones are used. Small extension of AYD-001's reminder resolution;
> doesn't redefine it.

## What (goal)
Give every timed Event at least one Reminder: if resolving RN-04 yields an empty popup set,
fall back to a single Reminder of **5 minutes** before start. If it yields one or more popup
Reminders, respect only those (no fallback added).

> Introduces business rule **RN-06**: when an Event's resolved popup Reminders (RN-04) are
> empty, add exactly one 5-minutes-before Reminder; otherwise use the resolved set unchanged.

## Acceptance criteria
```gherkin
Scenario: Event with no popup Reminder gets the 5-minute fallback
  Given an Event whose reminders.useDefault is true
  And the calendar has no popup default Reminders
  When its popup Reminders are resolved
  Then the resolved minutes are exactly [5]

Scenario: Event that opts out of Reminders gets the fallback
  Given an Event whose reminders.useDefault is false
  And reminders.overrides has no popup entry
  When its popup Reminders are resolved
  Then the resolved minutes are exactly [5]

Scenario: Existing popup Reminders are respected, no fallback
  Given an Event with a 10-minute popup Reminder
  When its popup Reminders are resolved
  Then the resolved minutes are exactly [10]
  And 5 is not added

Scenario: Multiple existing Reminders are all kept
  Given an Event with popup Reminders at 10 and 30 minutes
  When its popup Reminders are resolved
  Then the resolved minutes are exactly [10, 30]

Scenario: Non-popup Reminders still fall back
  Given an Event whose only Reminder is an email override (no popup)
  When its popup Reminders are resolved
  Then the resolved minutes are exactly [5]
```

## How (approach)
Change `ReminderResolver.popupReminderMinutes` (the single, pure resolution point used by
`CalendarService`): after filtering to popup minutes per RN-04, if the result is empty return
`[defaultReminderMinutes]` (a `5` constant); otherwise return it unchanged. Every downstream
step (Trigger creation, dedupe id `calendarId#eventId#5`, scheduling) already works from the
returned minutes, so no other module changes.

## Steps
1. `ReminderResolver.swift`: add `static let defaultReminderMinutes = 5`. At the end of
   `popupReminderMinutes`, compute the popup minutes, then
   `return minutes.isEmpty ? [defaultReminderMinutes] : minutes`.

## Affected files
- `cal-reminder/Calendar/ReminderResolver.swift`
- `cal-reminderTests/ReminderResolverTests.swift`

## Tests
- **Acceptance:** one `ReminderResolverTests` case per Gherkin scenario above, driving
  `ReminderResolver.popupReminderMinutes` directly with hand-built `GoogleEvent` +
  `calendarDefaults` (no I/O, matches AYD-001's pure-function boundary).
- **Unit:** empty resolved set → `[5]`; non-empty set returned untouched (order and values);
  email-only override → `[5]`.

## Checklist
- [ ] Event with no popup Reminder resolves to `[5]` (`ReminderResolverTests`)
- [ ] Event that opts out (useDefault=false, no popup override) resolves to `[5]` (`ReminderResolverTests`)
- [ ] Existing popup Reminders are returned unchanged, no `5` added (`ReminderResolverTests`)
- [ ] Email-only Reminder falls back to `[5]` (`ReminderResolverTests`)
