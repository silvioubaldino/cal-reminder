---
id: AYD-012
type: design
status: draft
updated: 2026-09-16
parents: [RF-17, RNF-13, RNF-12]
children: [SPEC-022, SPEC-023]
related: [GLO, AYD-009, TDR-007, TDR-008]
supersedes: []
superseded_by: null
---

# AYD-012: Observability and the Project Service

> Analysis & Design of the first project-owned backend: what a **Distributed Build** reports and
> what receives it (RF-17, RNF-13). Source of the design — the SPECs implement it.

## Goal
Three questions, and no others:

1. **How many airplanes flew?**
2. **How many Installs were used on a given day, on which app and macOS version?**
3. **How many installations happened**, split into first installs and updates?

Everything reported is an additive count, so the Project Service is stateless: no database, no
scheduled job, no aggregation. A handler validates a batch, increments counters, and answers.

## Affected modules
| Module | Role in this feature | Generated SPEC |
|--------|----------------------|----------------|
| **Project Service** *(new, `service/`)* | Go service on Cloud Run: `POST /v1/events`; owns the metric allowlist and the OTel export | SPEC-022 |
| **Cloud Monitoring** *(new integration)* | Where every metric lands; Grafana reads it as a datasource | SPEC-022 |
| **TelemetryClient** *(new, app)* | Accumulates pending events, enforces the once-a-day rule, sends the batch, honours the switch and the configuration gate | SPEC-023 |
| **AppDelegate / AppCoordinator** | Builds the client from configuration, or does not; reports the installation on launch and the new day on launch and on wake | SPEC-023 |
| **OverlayPresenter** | Reports each Reminder animation played, and the new day with it | SPEC-023 |
| **MenuBar UI** | States that Telemetry is on and offers the switch; carries the first-launch notice | SPEC-023 |

`architecture.md` gains the Project Service, Cloud Monitoring and Grafana in the same change.

## Interfaces / contract (source of truth)

**`POST /v1/events`** — sent when the pending batch is non-empty, at most hourly
```
{ "appVersion": "1.4.2",
  "macosMajor": "15",
  "events": [ { "name": "planes_flown", "value": 3 },
              { "name": "daily_active", "value": 1 },
              { "name": "installation",  "value": 1, "kind": "update" } ] }
→ 202 Accepted   (no body)
```

Every request carries `X-Telemetry-Key: <build-time key>`; without it, 401 and nothing recorded.
**No request carries an identifier of any kind.**

**Allowlist** — held server-side; a name outside it is dropped and the rest of the batch still
counts. A metric name is what creates a time series, so it is never free-form.
```
planes_flown   counter · label app_version               · value 1..1000
daily_active   counter · labels app_version, macos_major  · value == 1
installation   counter · labels app_version, kind         · value == 1
                         kind ∈ { first_install, update }
```

**Metrics**
| Metric | Kind | Labels | Answers |
|---|---|---|---|
| `planes_flown_total` | counter | `app_version` | Airplanes per hour / per day |
| `daily_active_total` | counter | `app_version`, `macos_major` | Installs used that day — read one bar per day |
| `installations_total` | counter | `app_version`, `kind` | Installations that ran at least once, first install vs update |

**App-side configuration gate** — mirrors `UpdateConfiguration`
(`cal-reminder/Update/UpdateController.swift:14`)
```
struct TelemetryConfiguration {
    let endpoint: URL
    let key: String
    static func make(endpoint: String?, key: String?) -> TelemetryConfiguration?   // nil when either is absent
}

protocol TelemetryReporting: AnyObject {
    var isConfigured: Bool { get }     // false in a Source Build
    var isEnabled: Bool { get set }    // the menu bar switch (RF-17)
    func recordPlaneFlown()
    func recordActiveToday()           // idempotent within a local calendar day
    func recordInstallationIfChanged() // first_install when no version was stored, update when it differs
}
```

`endpoint` and `key` ride the same road as the OAuth credentials and the Sparkle keys — an
untracked `Secrets.xcconfig`, injected by CI, surfaced through `Info.plist` (TDR-007, SPEC-018).
A **Source Build** has neither, so `make` returns `nil`, no client is constructed, no timer is
scheduled and no request is ever made.

## Affected domain model
- **Telemetry** *(new)* — a batch of named counter events. Counts and versions only, no identifier.
- **Project Service** *(new)* — the only project-owned server the app talks to besides the
  Release host.
- **Install** — the unit being counted, counted **without being identified**: the app reports at
  most one "used today" event per Install per day and the service sums them.
- Unchanged: Account, Calendar, Event, Reminder, Trigger, Overlay.

## Flow

```mermaid
sequenceDiagram
    autonumber
    participant A as App macOS
    participant S as Project Service
    participant M as Cloud Monitoring
    participant G as Grafana

    Note over A: launch, wake, animation or timer tick - first one of a new local day -> queue daily_active
    Note over A: no stored version -> queue installation first_install; different version -> update
    Note over A: a Reminder animation plays -> pending planes_flown ++

    A->>S: POST /v1/events - appVersion, macosMajor, batch
    S->>S: drop names outside the allowlist, validate ranges
    S->>M: increment each counter
    S-->>A: 202
    Note over A: the pending batch is cleared only after the 202

    G->>M: reads Cloud Monitoring as a datasource
```

## Decisions

- **"Used today" is deduped in the app, by local calendar day** — a stored date compared against
  today, not an elapsed-time check. It is checked from four places, and is idempotent, so extra
  call sites are free:

  | Trigger | Covers |
  |---|---|
  | Launch | a Mac powered on, or the app started by hand |
  | Wake from sleep | a Mac that slept overnight and woke with the app still running |
  | A Reminder animation played | an Install already up that did its job |
  | The hourly send timer | a Mac left awake for days with no animation |

  Wake is the one that matters: this is a menu bar agent that starts at login and stays up for
  days, so the usual way a Mac "comes back" is waking, with no launch at all.
  `AppCoordinator.handleWake()` already exists for AYD-011.

- **`daily_active_total` counts Installs whose app was running on an awake Mac that day**, among
  those with Telemetry switched on. It is not unique users, and it is a lower bound.
- **It is read bucketed by day.** Summed over a longer window it is Install-days, not distinct
  Installs — the same Mac appears once per day. The dashboard shows one bar per day and says so.
- **The pending batch is cleared only after a `202`.** An offline or sleeping Mac accumulates and
  reports late; an animation is never lost, only delayed.
- **Metric names come from a server-side allowlist**, because a client that can invent a name can
  invent time series, and time series cost money.
- **One endpoint for every counter.** Adding a metric is an allowlist entry and a call site.
- **The test animation does not count**, and neither does a relaunch on the same day.
- **The build-time key excludes Source Builds and nothing more.** It is a static shared secret in
  a binary whose source is public, so it authenticates nobody and nothing commercial is ever
  decided from it.
- **`--max-instances` is part of the design**, not an ops detail: it is what turns a flood into a
  503 instead of an invoice.
- **No Collector sidecar; the SDK exports straight to Cloud Monitoring** — TDR-008.
- **The service lives in `service/`, in this repository, public.** It makes the project multi-part;
  `conventions.md` §A.1 is updated in the same change.

## Out of scope
- **Crash reporting (RF-18).** A crash is a document, not a count; it needs symbolication,
  grouping and a retention story. Its own AYD.
- **Counting distinct Installs**, and everything that needs it: 7- and 30-day actives, retention,
  cohorts, total Installs ever. They become answerable when subscriptions bring an identity.
- **Accounts and Calendars per Install.**
- **Subscriptions, entitlements, feature locks, per-Install authentication.**
- **Logs and traces.** Counters only.
- **The landing page, download and Homebrew counts** — GitHub and Homebrew publish those already.
