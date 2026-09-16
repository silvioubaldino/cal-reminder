---
id: SPEC-023
type: spec
status: draft
updated: 2026-09-16
parents: [AYD-012]
related: [SPEC-022, SPEC-018, RF-17, RNF-13, RNF-12, GLO, REQ-01]
---

# SPEC-023: Telemetry client in the app — what + how

> Implements the app half of AYD-012: the Install identifier, the two reports, the menu bar
> switch, and the configuration gate that keeps a **Source Build** silent. Depends on
> **SPEC-022** for the endpoints and on **SPEC-018** for the untracked config the endpoint and key
> land in.

## What (goal)
1. An Install identifier — a UUID generated on first launch and kept in the Keychain, so it
   survives reinstallation.
2. `/v1/events` sent hourly, carrying the number of Reminder animations played since the last
   accepted report, and **skipped entirely** when that number is zero.
3. `/v1/state` sent on launch and every 24 h thereafter, carrying versions, connected Accounts and
   selected Calendars.
4. A menu bar item that says Telemetry is on and switches it off, plus a first-launch notice shown
   before the first report leaves the Mac.
5. With no `TELEMETRY_ENDPOINT` or no `TELEMETRY_KEY` in the build, **no request is ever made** —
   proven by a test, because it is what RNF-13 promises about a Source Build.

Out of scope: crash reports (SPEC-024); anything the `/v1/state` response might carry later.

## Acceptance criteria
```gherkin
Scenario: A Source Build is silent
  Given the build carries no TELEMETRY_ENDPOINT or no TELEMETRY_KEY
  Then TelemetryConfiguration.make returns nil
  And no TelemetryClient is constructed, no timer is scheduled and no request is ever made
  And the menu bar shows no Telemetry item

Scenario: The Install identifier is stable
  Given the app launches for the first time
  Then a UUID is generated and stored in the Keychain
  And every later launch reports that same identifier
  And deleting and reinstalling the app keeps it

Scenario: Animations are counted and reported hourly
  Given 3 Reminder animations have played since the last accepted report
  When the hourly report is due
  Then POST /v1/events is sent with planesFlown 3

Scenario: An idle hour sends nothing
  Given no animation has played since the last accepted report
  When the hourly report is due
  Then no request is made

Scenario: A failed report never loses an animation
  Given 3 animations are pending and the request fails
  Then the pending count stays 3
  And 2 more animations later make the next report carry 5

Scenario: The pending count is cleared only on acceptance
  Given the service answers 202
  Then the pending count returns to 0

Scenario: State is reported on launch and then daily
  Given the app launches and the last state report is older than 24 hours
  Then POST /v1/state is sent with the current versions, Account count and Calendar count
  And a Mac that is asleep at any given hour still reports on its next launch or when 24 hours
      have elapsed while awake

Scenario: The switch stops everything
  Given the user turns Telemetry off in the menu bar
  Then no further request is made, the pending count is discarded
  And the choice survives a restart

Scenario: The first launch says so before reporting
  Given the app has never shown the Telemetry notice
  Then the notice is shown and no report is sent until it has been
```

## How (approach)
- **`TelemetryConfiguration.make(endpoint:key:)` mirrors `UpdateConfiguration.make`**
  (`cal-reminder/Update/UpdateController.swift:14`): `nil` when either value is missing, and
  `AppCoordinator` simply does not build a client. This is the gate; nothing downstream needs to
  know about Source Builds.
- **The identifier reuses `KeychainStore`**, under its own key, separate from any Account's
  tokens (TDR-005's scoping is untouched).
- **Two independent timers**, one per report, each with its own persisted "last sent" timestamp in
  `UserDefaults` — elapsed-time checks, never a wall-clock hour, so a Mac that sleeps through a
  fixed time still reports.
- **The pending animation count is persisted** so a quit or a crash does not lose it, and is
  cleared only after a `202`.
- **`OverlayPresenter` calls `recordPlaneFlown()`** when an animation actually plays; the test
  animation does not count.
- **Settings follow `UpdateSettings.swift`**: a `TelemetrySettingsStoring` protocol with a
  `UserDefaults` implementation, so the tests inject a fake.

## Steps
1. `TelemetryConfiguration` + the `Info.plist` keys, added to `Config/Secrets.example.xcconfig`
   and `project.yml` alongside `SUFeedURL` (SPEC-018).
2. `InstallIdentity`: read-or-create the UUID through `KeychainStore`.
3. `TelemetrySettings`: the on/off flag and the "notice shown" flag.
4. `TelemetryClient`: pending count, the two timers, the two requests, `X-Telemetry-Key`,
   short timeouts, no retry storm — a failure just waits for the next tick.
5. Wire it in `AppCoordinator`; supply the Account and Calendar counts from `AccountRegistry`.
6. `OverlayPresenter` reports each played animation.
7. Menu bar: the Telemetry item and the switch; the first-launch notice.
8. README: what is reported, what is not, and how to turn it off.

## Affected files
- `cal-reminder/Telemetry/` — `TelemetryConfiguration.swift`, `InstallIdentity.swift`,
  `TelemetrySettings.swift`, `TelemetryClient.swift` (new)
- `cal-reminder/App/AppCoordinator.swift`
- `cal-reminder/Overlay/OverlayPresenter.swift`
- `cal-reminder/MenuBar/StatusMenuController.swift`
- `cal-reminder/App/Info.plist`, `project.yml`, `Config/Secrets.example.xcconfig`
- `README.md`

## Tests
- **Acceptance:** one test per Gherkin scenario, with the HTTP boundary and the Keychain faked.
- **Unit:** the pending count across failure, success and a restart; the elapsed-time due checks
  against an injected clock; `TelemetryConfiguration.make` with each field missing.
- **The Source Build test is the important one:** with a `nil` configuration, assert the fake HTTP
  client recorded **zero** requests over a full simulated day, including launch. RNF-13 names it.

## Checklist
- [ ] No Event title, Calendar name, Account email or identifier is ever in a payload
- [ ] The test animation does not count as a played animation
- [ ] The switch is discoverable, and the notice precedes the first report
- [ ] `nil` configuration means zero requests, asserted by a test
