---
id: SPEC-023
type: spec
status: draft
updated: 2026-09-16
parents: [AYD-013]
related: [SPEC-024@service, SPEC-018, RF-17, RNF-13, RNF-12, GLO, REQ-01]
---

# SPEC-023: Telemetry client in the app — what + how

> Implements the app half of AYD-013: three counter events, the once-a-day rule, the menu bar
> switch, and the configuration gate that keeps a **Source Build** silent. Depends on
> `SPEC-024@service` for the endpoint and on **SPEC-018** for the untracked config the endpoint
> and key land in.

## What (goal)
1. Three events, accumulated locally and sent as one batch, at most hourly:
   - `planes_flown` — Reminder animations played since the last accepted batch.
   - `daily_active` — once per local calendar day, queued by whichever comes first: a launch, a
     wake from sleep, a Reminder animation, or an hourly timer tick.
   - `installation` — once per installation, `kind: first_install` when no version was ever
     stored, `kind: update` when the stored one differs from the running one.
2. A menu bar item that says Telemetry is on and switches it off, plus a first-launch notice shown
   before the first batch leaves the Mac.
3. **No identifier of any kind** is generated, stored or sent.
4. With no `TELEMETRY_ENDPOINT` or no `TELEMETRY_KEY` in the build, no request is ever made —
   proven by a test, because it is what RNF-13 promises about a Source Build.

Out of scope: everything AYD-013 lists under §Out of scope.

## Acceptance criteria
```gherkin
Scenario: A Source Build is silent
  Given the build carries no TELEMETRY_ENDPOINT or no TELEMETRY_KEY
  Then TelemetryConfiguration.make returns nil
  And no TelemetryClient is constructed, no timer is scheduled and no request is ever made
  And the menu bar shows no Telemetry item

Scenario: Animations accumulate and are sent as a batch
  Given 3 Reminder animations have played since the last accepted batch
  When the send is due
  Then POST /v1/events carries planes_flown 3

Scenario: Nothing pending sends nothing
  Given the pending batch is empty
  When the send is due
  Then no request is made

Scenario: Used-today is reported once per calendar day
  Given the app launches on a day it has not yet reported
  Then daily_active 1 is queued
  And a second launch on the same day queues nothing

Scenario: A Mac that wakes without relaunching still counts
  Given the app has been running since yesterday and never relaunched
  And the Mac slept overnight and wakes today
  Then daily_active 1 is queued on wake

Scenario: A Mac left awake for days still counts each day
  Given the app has been running with no launch, no wake and no animation
  When the hourly timer ticks on a new calendar day
  Then daily_active 1 is queued

Scenario: An animation also counts the day
  Given no launch, wake or tick has reported today yet
  When a Reminder animation plays
  Then daily_active 1 is queued

Scenario: Used-today survives a restart
  Given daily_active was already sent today
  When the app is quit and launched again the same day
  Then nothing is queued

Scenario: A new day reports again
  Given daily_active was sent yesterday
  When the app is used today
  Then daily_active 1 is queued once

Scenario: A first install is reported once
  Given no version has ever been stored
  When the app launches
  Then installation 1 is queued with kind first_install
  And the next launch queues nothing

Scenario: An update is reported once
  Given the last version seen was 1.4.1 and the running version is 1.4.2
  When the app launches
  Then installation 1 is queued with kind update and appVersion 1.4.2
  And the next launch on the same version queues nothing

Scenario: A failed send never loses an event
  Given a batch is pending and the request fails
  Then the pending batch is unchanged
  And later events are added to it and sent together

Scenario: The pending batch is cleared only on acceptance
  Given the service answers 202
  Then the pending batch is emptied

Scenario: The switch stops everything
  Given the user turns Telemetry off in the menu bar
  Then no further request is made, the pending batch is discarded
  And the choice survives a restart

Scenario: The first launch says so before reporting
  Given the app has never shown the Telemetry notice
  Then the notice is shown and nothing is sent until it has been

Scenario: The test animation does not count
  Given the user triggers the test animation from the menu bar
  Then planes_flown does not increase
```

## How (approach)
- **`TelemetryConfiguration.make(endpoint:key:)` mirrors `UpdateConfiguration.make`**
  (`cal-reminder/Update/UpdateController.swift:14`): `nil` when either value is missing, and
  `AppCoordinator` does not build a client.
- **The pending batch is persisted** in `UserDefaults` so a quit or a crash does not lose it, and
  is cleared only after a `202`.
- **The daily rule is a stored date**, compared against today in the current local calendar. It is
  checked from four places — launch, wake, animation, timer tick — and is idempotent.
- **The installation rule is a stored version string**: absent means `first_install`, different
  means `update`, equal means nothing.
- **One timer**, hourly, that sends only when the batch is non-empty; a failure waits for the next
  tick, with no retry.
- **Settings follow `UpdateSettings.swift`**: a `TelemetrySettingsStoring` protocol with a
  `UserDefaults` implementation.

## Steps
1. `TelemetryConfiguration` + the `Info.plist` keys, added to `Config/Secrets.example.xcconfig`
   and `project.yml` alongside `SUFeedURL` (SPEC-018).
2. `TelemetrySettings`: the on/off flag, the "notice shown" flag, the last reported day, the last
   seen version, and the pending batch.
3. `TelemetryClient`: queue, hourly timer (which also runs the day check), batch request with
   `X-Telemetry-Key`, short timeout.
4. Wire it in `AppCoordinator`: `recordActiveToday()` on launch and inside `handleWake()`, and
   `recordInstallationIfChanged()` on launch.
5. `OverlayPresenter` calls `recordPlaneFlown()` and `recordActiveToday()` on a real animation.
6. Menu bar: the Telemetry item and the switch; the first-launch notice.
7. README: what is reported, what is not, that it carries no identifier, and how to turn it off.

## Affected files
- `cal-reminder/Telemetry/` — `TelemetryConfiguration.swift`, `TelemetrySettings.swift`,
  `TelemetryClient.swift` (new)
- `cal-reminder/App/AppCoordinator.swift`
- `cal-reminder/Overlay/OverlayPresenter.swift`
- `cal-reminder/MenuBar/StatusMenuController.swift`
- `cal-reminder/App/Info.plist`, `project.yml`, `Config/Secrets.example.xcconfig`
- `README.md`

## Tests
- **Acceptance:** one test per Gherkin scenario, with the HTTP boundary and the clock faked.
- **Unit:** the daily rule across a day boundary, across a restart and across each of the four
  call sites (idempotent within a day); the installation rule for absent, different and equal
  stored versions; the pending batch across failure, success and relaunch;
  `TelemetryConfiguration.make` with each field missing.
- **Source Build:** with a `nil` configuration, assert the fake HTTP client recorded **zero**
  requests over a full simulated day, including launch (RNF-13).

## Checklist
- [ ] No identifier is generated, stored or sent anywhere
- [ ] No Event title, Calendar name or Account email can reach a payload
- [ ] The test animation does not count
- [ ] Waking from sleep reports the new day without a relaunch
- [ ] `nil` configuration means zero requests, asserted by a test
