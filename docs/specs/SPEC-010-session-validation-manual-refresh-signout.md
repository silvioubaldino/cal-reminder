---
id: SPEC-010
type: spec
status: done
parents: [AYD-001]
related: [GLO, REQ-01]
updated: 2026-07-16
---

# SPEC-010: Session validation, manual refresh, and sign-out — what + how

> Make "Connected" mean the session actually works, not just that a token sits in the
> Keychain. Adds startup verification, auth-failure-driven re-auth prompting, a manual Poll
> from the empty state, a 5-minute Poll cadence, and a Google sign-out. Extends AYD-001's
> AuthManager / AppCoordinator / MenuBar contracts; doesn't redefine them.

## What (goal)
Four coordinated changes:
1. **Real connection state.** Replace the `connected: Bool` (derived from token *presence*)
   with an explicit `ConnectionStatus` that reflects a *verified* session. Verify on startup
   and, on an auth-fatal failure (revoked/expired refresh token), clear the dead token and
   move to `needsReauth` — never on a transient network failure (RNF-04).
2. **Manual Poll from the empty state (RF-12).** When there is no upcoming Trigger, the
   next-Trigger menu row becomes a clickable "refresh" that fires an immediate Poll.
3. **5-minute Poll cadence.** Reduce the background Poll interval from ~120s to 300s.
4. **Sign out of Google.** A menu action that disconnects the account (clears the token,
   cancels armed Triggers, resets to disconnected).

> Extends **RF-06** (menu now also offers "Refresh now" and "Sign out of Google") and adds
> **RF-12** (Should — manual Poll). Refines **RNF-04**: only auth-fatal failures drop the
> session; network loss preserves it.

## Model
```
enum ConnectionStatus: Equatable {
  case disconnected           // no refresh token in the Keychain
  case connecting             // token present, verifying
  case connected(email: String?)  // verified session; email once fetched
  case needsReauth            // token present but dead (invalid_grant / 401 after refresh)
}
```
`AppState.connected: Bool` and `AppState.userEmail: String?` are replaced by
`AppState.connectionStatus: ConnectionStatus` (menu text derives from it).

## Acceptance criteria
```gherkin
Scenario: Startup with a valid session shows the email
  Given a refresh token is stored
  And the account's email is fetchable
  When the app starts
  Then the status is connected with that email
  And the menu reads "Connected as <email>"

Scenario: Startup with a revoked token prompts re-auth
  Given a refresh token is stored
  And refreshing it returns invalid_grant
  When the app starts
  Then the stored refresh token is cleared
  And the status is needsReauth
  And the menu prompts to reconnect

Scenario: Poll failing on a revoked token drops the session
  Given a connected session
  When a Poll's authenticated call returns invalid_grant
  Then the refresh token is cleared
  And the status becomes needsReauth

Scenario: Poll failing on a network error keeps the session
  Given a connected session
  When a Poll fails with a network error
  Then the refresh token is NOT cleared
  And the status stays connected

Scenario: Refresh from the empty state triggers a Poll
  Given the status is connected
  And there is no upcoming Trigger
  When the user clicks the next-Trigger row
  Then a manual Poll runs
  And the menu shows a refreshing state while it runs

Scenario: Refresh control is hidden when a Trigger is upcoming
  Given there is an upcoming Trigger
  When the menu renders
  Then the next-Trigger row shows "Next: <title> <time>" and is not clickable

Scenario: Background Poll runs every 5 minutes
  Given the app is running
  Then the Poll interval is 300 seconds

Scenario: Sign out disconnects the account
  Given a connected session with armed Triggers
  When the user chooses "Sign out of Google"
  Then the refresh token is removed from the Keychain
  And all armed Triggers are cancelled
  And the status becomes disconnected
```

## How (approach)
- **AuthManager** grows an auth-fatal error and a `disconnect()`. On a refresh that returns
  `invalid_grant`, it clears the stored refresh token and throws `AuthError.refreshTokenRevoked`;
  all other non-200s stay `tokenExchangeFailed`. `disconnect()` clears the token + token cache.
- **CalendarService.poll** stops swallowing auth-fatal errors: the per-Calendar `catch`
  rethrows `AuthError.refreshTokenRevoked` (network / other errors are still skipped per
  Calendar as today).
- **AppCoordinator** owns `ConnectionStatus`. `start()` verifies via `auth.userEmail()`
  (`connecting` → `connected(email)` / `needsReauth` / stay `connecting` on network error).
  `poll()`'s `catch` classifies: `refreshTokenRevoked` → `needsReauth`; else keep the current
  status. Adds `refreshNow()` (sets a transient `refreshing` flag, runs `poll()`) and
  `logout()` (`scheduler.cancelAll()` + `auth.disconnect()` + reset to `disconnected`).
- **StatusMenuController** renders status text from `ConnectionStatus`; when the status is
  `connected`/`needsReauth` and `nextTrigger == nil`, the next-Trigger row gets the
  `arrow.clockwise` image, becomes enabled, and calls `onRefresh` (title "Refreshing…" while
  `refreshing`). Adds a "Sign out of Google" item, visible only when there is a session.

## Steps
1. `AppState.swift`: replace `connected`/`userEmail` with `connectionStatus: ConnectionStatus`;
   add `refreshing: Bool`. Add the `ConnectionStatus` enum (own file or alongside `AppState`).
2. `AuthManager.swift`: add `AuthError.refreshTokenRevoked`; in the refresh path, parse the
   error body and, on `invalid_grant`, `tokenStore.setRefreshToken(nil)` + throw
   `refreshTokenRevoked`. Add `disconnect()` to the protocol + impl (clear token + cached
   access token). Keep `authorizedRequest`'s 401-retry, but if the retry's refresh is revoked
   it surfaces `refreshTokenRevoked`.
3. `CalendarService.swift`: in `poll()`'s per-Calendar `catch`, rethrow when the error is
   `AuthError.refreshTokenRevoked`; otherwise skip that Calendar as today.
4. `AppCoordinator.swift`: introduce `connectionStatus`; rewrite `start()` verification,
   `poll()` error classification, `reconnect()`/`logout()` transitions; add `refreshNow()`
   and `logout()`; default `pollInterval` 120 → 300.
5. `PollLoop.swift`: default interval 120 → 300.
6. `StatusMenuController.swift`: render from `ConnectionStatus`; wire `onRefresh` on the
   empty next-Trigger row (icon + enabled + "Refreshing…"); add the "Sign out of Google"
   item with `onSignOut`, shown only when there is a session.
7. `AppDelegate.swift`: pass `onRefresh` → `coordinator.refreshNow()` and `onSignOut` →
   `coordinator.logout()`.

## Affected files
- `cal-reminder/App/AppState.swift`
- `cal-reminder/Auth/AuthManager.swift`
- `cal-reminder/Calendar/CalendarService.swift`
- `cal-reminder/App/AppCoordinator.swift`
- `cal-reminder/App/PollLoop.swift`
- `cal-reminder/MenuBar/StatusMenuController.swift`
- `cal-reminder/App/AppDelegate.swift`
- `cal-reminderTests/AppCoordinatorTests.swift`
- `cal-reminderTests/AuthManagerTests.swift`
- `cal-reminderTests/CalendarServiceTests.swift`

## Tests
- **Acceptance:** one `AppCoordinatorTests` case per coordinator-facing scenario, using a
  fake `AuthManaging` that can return an email, throw `refreshTokenRevoked`, or throw a
  network error — asserting the resulting `ConnectionStatus` and that `disconnect()`/
  `cancelAll()` are (or are not) called. `AuthManagerTests`: `invalid_grant` refresh clears
  the token and throws `refreshTokenRevoked`; a non-`invalid_grant` non-200 throws
  `tokenExchangeFailed`; `disconnect()` clears the token. `CalendarServiceTests`: a per-Calendar
  `refreshTokenRevoked` propagates out of `poll()`; a network error is still skipped.
- **Unit:** `pollInterval` default is 300; `refreshNow()` sets then clears `refreshing`;
  `logout()` resets to `.disconnected`.

## Checklist
- [x] Valid session on startup → `connected(email)`, menu shows "Connected as <email>"
- [x] Revoked token on startup → token cleared, `needsReauth`, menu prompts reconnect
- [x] Poll auth-fatal failure → token cleared, `needsReauth`
- [x] Poll network failure → session preserved, token intact
- [x] Empty state row triggers a manual Poll and shows "Refreshing…"
- [x] Refresh control hidden when a Trigger is upcoming
- [x] Background Poll interval is 300s
- [x] Sign out clears the token, cancels Triggers, → `disconnected`
