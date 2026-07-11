---
id: SPEC-002
type: spec
status: draft
updated: 2026-07-11
parents: [AYD-001]
related: [GLO]
---

# SPEC-002: Google auth + calendar poll → Triggers

> Builds **AuthManager** (OAuth PKCE + Keychain) and **CalendarService** (poll, parse
> timed Events, resolve popup Reminders → `[Trigger]`). Read-only Calendar access (M2).

## What (goal)
Authorize once in the browser, keep the connection across restarts via a Keychain refresh
token, and on each `poll()` return the `[Trigger]` for the next window (timed Events only,
popup Reminders resolved per RN-04), meeting RF-01..RF-03.

## Acceptance criteria
```gherkin
Scenario: One-time authorization persists
  Given the app has never connected
  When the user runs "Reconnect Google" and authorizes in the browser
  Then the refresh token is stored in the Keychain (never in plaintext on disk)
  And after an app restart the app is connected without re-authorizing

Scenario: Access token auto-refresh
  Given a valid refresh token and an expired access token
  When a request returns 401
  Then AuthManager refreshes the access token and retries once transparently

Scenario: Only timed events produce Triggers
  Given the calendar has a timed Event and an all-day Event
  When poll() runs
  Then only the timed Event yields Triggers (all-day ignored, RN-01)

Scenario: Resolve popup reminders (RN-04)
  Given an Event with reminders.useDefault = true
  When poll() runs
  Then its Triggers use the calendar's default reminders, keeping only method == popup
  And given an Event with overrides, only its popup overrides are used

Scenario: One Trigger per popup reminder
  Given a timed Event with popup reminders [10, 2] minutes
  When poll() runs
  Then two Triggers are emitted with fireDate = start − 10 and start − 2 (RN-02)
  And each id is "<eventId>#<minutes>" (RN-03)
```

## How (approach)
`AuthManager`: OAuth 2.0 Desktop/PKCE — loopback redirect (`http://127.0.0.1:<port>`),
open the system browser, capture the code, exchange for tokens, store **refresh token** in
Keychain (`kSecClassGenericPassword`). `accessToken()` refreshes on demand and on 401.
`CalendarService.poll()`: `GET events.list` (`timeMin=now`, `timeMax=now+2h`,
`singleEvents=true`, `syncToken` when available for incremental sync, RNF-06); decode with
`Codable`; filter `start.dateTime` present; resolve reminders (fetch `calendarList.get`
defaults once, cache) → map to `[Trigger]`. Boundaries (network, keychain, clock) are
injected for tests.

## Steps
1. `KeychainStore` — get/set/delete the refresh token (`kSecClassGenericPassword`).
2. `AuthManager` — PKCE (verifier/challenge), loopback listener, code→token exchange, refresh, `accessToken()`, `connect()`, `isConnected`.
3. `GoogleCalendarAPI` — thin `URLSession` client: `events.list`, `calendarList.get`; `Codable` DTOs; `syncToken` handling.
4. `ReminderResolver` — pure: `(event, calendarDefaults) -> [Reminder]` applying RN-04 (popup-only).
5. `CalendarService.poll()` — orchestrate fetch → filter timed → resolve reminders → `[Trigger]` (RN-01/02/03).

## Affected files
- `cal-reminder/Auth/KeychainStore.swift`
- `cal-reminder/Auth/AuthManager.swift`
- `cal-reminder/Calendar/GoogleCalendarAPI.swift`
- `cal-reminder/Calendar/Models.swift` (Event/Reminder DTOs)
- `cal-reminder/Calendar/ReminderResolver.swift`
- `cal-reminder/Calendar/CalendarService.swift`
- `cal-reminderTests/ReminderResolverTests.swift`
- `cal-reminderTests/CalendarServiceTests.swift`
- `cal-reminderTests/AuthManagerTests.swift`

## Tests
- **Acceptance:** timed-only, RN-04 resolution, one-Trigger-per-reminder, and id format → `CalendarServiceTests`/`ReminderResolverTests` with a stubbed API returning fixture JSON and a fixed clock. Auto-refresh → `AuthManagerTests` with a stubbed token endpoint (401→refresh→retry). One-time-persist verified **manually** (real browser + Keychain) plus a `KeychainStore` round-trip unit test.
- **Unit:** PKCE challenge derivation; `syncToken` incremental vs full; `fireDate` math; DTO decoding (all-day vs timed).

## Checklist
- [ ] Browser authorize → refresh token in Keychain; survives restart
- [ ] 401 triggers one transparent refresh + retry
- [ ] All-day Events ignored
- [ ] RN-04 popup resolution (useDefault vs overrides)
- [ ] One Trigger per popup reminder, correct id + fireDate
- [ ] Incremental sync via syncToken
