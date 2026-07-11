---
id: SPEC-002
type: spec
status: review
updated: 2026-07-11
parents: [AYD-001]
related: [GLO, TDR-001]
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
`AuthManager`: OAuth 2.0 Desktop/PKCE — a loopback `NWListener` on an ephemeral port
(`http://127.0.0.1:<port>`) opens the system browser and captures Google's redirect,
exchanges the code for tokens, and stores the **refresh token** in Keychain
(`kSecClassGenericPassword`). `accessToken()` returns the cached token until it expires,
then refreshes. `authorizedRequest(_:)` builds a request with a fresh token, sends it, and
on a `401` refreshes once and retries transparently — callers (`GoogleCalendarAPI`) go
through this method instead of handling 401 themselves. Client credentials come from a
local JSON file, never committed (TDR-001).
`CalendarService.poll()`: `GET events.list` (`timeMin=now`, `timeMax=now+2h`,
`singleEvents=true`, `syncToken` when available for incremental sync, RNF-06); decode with
`Codable`; filter `start.dateTime` present; resolve reminders (fetch `calendarList.get`
defaults once, cache) → map to `[Trigger]`. Boundaries (network, keychain, clock, browser/
loopback) are injected for tests.

## Steps
1. `KeychainStore` — get/set/delete the refresh token (`kSecClassGenericPassword`).
2. `AuthManager` — PKCE (verifier/challenge), loopback listener, code→token exchange, refresh, `accessToken()`, `connect()`, `isConnected`.
3. `GoogleCalendarAPI` — thin `URLSession` client: `events.list`, `calendarList.get`; `Codable` DTOs; `syncToken` handling.
4. `ReminderResolver` — pure: `(event, calendarDefaults) -> [Reminder]` applying RN-04 (popup-only).
5. `CalendarService.poll()` — orchestrate fetch → filter timed → resolve reminders → `[Trigger]` (RN-01/02/03).

## Affected files
- `cal-reminder/Auth/KeychainStore.swift`
- `cal-reminder/Auth/GoogleOAuthConfig.swift` (client credentials loader — see TDR-001)
- `cal-reminder/Auth/PKCE.swift` (verifier/challenge, pure)
- `cal-reminder/Auth/AuthorizationCodeProviding.swift` (loopback HTTP listener + browser)
- `cal-reminder/Auth/AuthManager.swift`
- `cal-reminder/Networking/HTTPClient.swift` (shared network boundary)
- `cal-reminder/Calendar/GoogleCalendarAPI.swift`
- `cal-reminder/Calendar/Models.swift` (Event/Reminder DTOs)
- `cal-reminder/Calendar/ReminderResolver.swift`
- `cal-reminder/Calendar/CalendarService.swift`
- `cal-reminderTests/ReminderResolverTests.swift`
- `cal-reminderTests/CalendarServiceTests.swift`
- `cal-reminderTests/AuthManagerTests.swift`
- `cal-reminderTests/KeychainStoreTests.swift`

## Tests
- **Acceptance:** timed-only, RN-04 resolution, one-Trigger-per-reminder, and id format → `CalendarServiceTests`/`ReminderResolverTests` with a stubbed API returning fixture JSON and a fixed clock. Auto-refresh → `AuthManagerTests` with a stubbed token endpoint (401→refresh→retry). One-time-persist verified **manually** (real browser + Keychain) plus a `KeychainStore` round-trip unit test.
- **Unit:** PKCE challenge derivation; `syncToken` incremental vs full; `fireDate` math; DTO decoding (all-day vs timed).

## Checklist
- [ ] Browser authorize → refresh token in Keychain; survives restart (manual — no
      "Reconnect Google" menu item yet; end-to-end wiring is SPEC-003)
- [x] 401 triggers one transparent refresh + retry (`AuthManagerTests`)
- [x] All-day Events ignored (`CalendarServiceTests`)
- [x] RN-04 popup resolution (useDefault vs overrides) (`ReminderResolverTests`, `CalendarServiceTests`)
- [x] One Trigger per popup reminder, correct id + fireDate (`CalendarServiceTests`)
- [x] Incremental sync via syncToken (`CalendarServiceTests`)
- [x] Refresh token round-trips through the Keychain (`KeychainStoreTests`)
