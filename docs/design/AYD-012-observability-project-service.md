---
id: AYD-012
type: design
status: draft
updated: 2026-09-16
parents: [RF-17, RNF-13, RNF-12]
children: [SPEC-022, SPEC-023]
related: [GLO, AYD-009, AYD-010, TDR-007, TDR-008]
supersedes: []
superseded_by: null
---

# AYD-012: Observability and the Project Service

> Analysis & Design of the first project-owned backend: what a **Distributed Build** reports,
> what receives it, and how the project turns that into numbers it can look at (RF-17, RNF-13). It **does not supersede AYD-009** — AYD-009 listed telemetry as a non-goal because
> RNF-12 forbade it at the time; RNF-12 has since been rewritten, and AYD-009's distribution
> design is untouched here. Source of the design — the SPECs implement it.

## Goal
Today the project ships an app and then goes blind. Nobody knows whether anyone opens it, on
which version, or whether the airplane ever flies. This design answers exactly
three questions, and deliberately no more:

1. **How many airplanes flew?** — is the app doing its job, and how often.
2. **How many Installs were used on a given day, on which version?** — is anyone there.
3. **How many installations happened, and were they new or an update?** — did a release get
   adopted, and is the base growing.

Non-goals, all of them chosen rather than deferred: counting distinct Installs with any
consistency; 7- and 30-day actives; retention and cohorts; total Installs ever; fleet totals of
Accounts and Calendars; subscriptions and entitlements; the landing page; download and Homebrew
counts (GitHub and Homebrew publish those for free); per-event streams.

**Crash reporting (RF-18) is out of this design.** A crash count is a fair metric, but the crash
itself is a document, not a number, and there is no cheap version of it: counting a crash already
requires the scanner that finds it. It also carries questions this AYD has no business answering —
symbolication against a release's dSYM, grouping identical crashes, how anyone actually reads them,
retention. It gets its own AYD.

## Analysis

### RNF-12 had to move first, and it did

RNF-12 used to forbid "phone-home" outright, and AYD-009 inherited that as a non-goal. The
requirement has been rewritten because the old wording conflated **gating** a capability behind a
server with **measuring** how the app is doing. The first is what "sold on trust" exists to rule
out; the second is ordinary product operation. What survives, and what this design must not
break, is that a **Source Build** is complete and silent: it contacts no project-owned server,
ever, and that is testable rather than promised (RNF-13).

### What counting distinct Installs would have cost

The obvious next question after "how many were used today" is "how many are still around after a
month". Answering it *consistently* requires remembering which Installs have been seen — which
means a per-Install identifier, a database holding one record each, a scheduled job to aggregate
the population, and a definition of "active" baked into that job. That is a database, a cron, a
rollup endpoint, a scale ceiling and a pile of design surface, in service of one class of answer.

This design does not buy it. Retention numbers are worth that machinery for a product with a
growth loop to tune; for a project that mainly needs to know whether anyone is there and whether
a release landed, they are not. **The `installId` is therefore gone entirely** — not stored, not
sent, not generated. With nothing to deduplicate server-side, the reports carry no identifier at
all, which is both less code and a materially better privacy story.

If subscriptions arrive, they bring their own identity (a per-Install key pair whose private half
never ships) and the retention questions become answerable again as a side effect. That is the
right moment to pay for it.

### Everything left is an additive counter

Dropping the population aggregates leaves only numbers that each request can contribute to
directly:

| What | Why it works from the request |
|---|---|
| Airplanes flown | Each report carries a delta; summing deltas across Installs is exactly right |
| Used today | Each Install contributes **at most one** per calendar day (see below), so the daily sum is the number of Installs used that day |
| Update installed | One event per Install per version change |

No value here is a level that goes up and down, so no gauge is published, and nothing needs to see
the whole fleet at once. The consequence is the shape of the whole service: **no database, no
scheduled job, no rollup, no aggregation.** A handler validates a batch, increments counters, and
answers.

### The daily dedupe moves to the client, and what counts as "used"

"Used today" is only a count of Installs if each Install reports it once. That is enforced in the
app: it keeps the last **local calendar day** on which it sent the event and queues the event the
first time it notices a new day. A second notice the same day adds nothing.

Calendar-day, not "24 hours elapsed": elapsed time drifts and can produce two events in one day or
none in another, while a date comparison dedupes exactly. Installs in different time zones smear
the boundary by a few hours, which does not matter at the resolution anyone reads this number.

**Where the check runs is what decides whether the number is right.** Launch alone is not enough:
this is a menu bar agent that starts at login and then stays up for days, so the most common way a
Mac "comes back" is waking from sleep, with no launch at all. Four call sites:

| Trigger | Covers |
|---|---|
| Launch | a Mac powered on, or the app started by hand |
| **Wake from sleep** | a Mac that slept overnight and woke with the app still running |
| A Reminder animation played | an Install that was already up and did its job |
| The hourly send timer | a Mac left awake for days with no animation |

The timer is the guarantee — worst case the event is an hour late. Launch and wake exist so it is
prompt. `AppCoordinator.handleWake()` already exists for AYD-011, so wake is one more call site.

What the number therefore is, stated plainly so nobody over-reads it: **Installs whose app was
running on an awake Mac at some point that day, among those with Telemetry switched on.** For a
menu bar agent that launches at login, "opened the app" is not an action a user really performs, so
this is the useful reading rather than a compromise. It is not unique users, and it is a lower
bound.

It is also only meaningful **bucketed by day**. Summing the counter over a seven-day window gives
Install-days, not distinct Installs — the same Mac appears seven times. The dashboard shows one bar
per day and says so.

### One endpoint, an allowlist of names

Every report is now the same shape — a name and a value — so there is one endpoint and one
payload. The metric name is **not** free-form: the service holds an allowlist, and an unknown name
is dropped. A metric name reaching Cloud Monitoring is what creates a time series, so letting a
client invent one is the one place a bad actor could cost real money.

Adding a metric later is one entry in that allowlist plus one call site in the app — no new route,
no new contract.

### The configuration gate is the Source Build guarantee

`TelemetryConfiguration.make(endpoint:key:)` returns `nil` when either value is absent, exactly as
`UpdateConfiguration.make(feedURL:publicKey:)` already does for Sparkle
(`cal-reminder/Update/UpdateController.swift:14`). With `nil`, no client is constructed, no timer
is scheduled, and no request is made. Both values ride the same road as the OAuth credentials and
the Sparkle keys — an untracked `Secrets.xcconfig`, injected by CI, surfaced through `Info.plist`
(TDR-007, SPEC-018). Whoever clones the repository has neither, so a Source Build is silent
without anyone remembering to make it so.

The key also separates a Distributed Build's reports from anonymous noise. It is a static shared
secret in a binary whose source is public, so it authenticates nobody — anyone determined extracts
it with `strings`. That is accepted deliberately: the goal is to exclude Source Builds from the
numbers and to raise the cost of casual abuse, not to prove provenance. Nothing commercial will
ever be decided from it.

### What bounds the damage is the instance cap

A public write endpoint on an autoscaling service turns a flood into an invoice. `--max-instances`
is therefore part of the design, not a tuning knob: with a cap, the worst case is that Telemetry
returns 503, which no user ever notices. A body-size limit, a cap on events per batch and a
per-IP rate limit bound the rest.

### Why a direct exporter and no Collector sidecar

One destination does not need a router, and a sidecar costs memory and cold start on a service
that handles a trickle. The SDK exports straight to Cloud Monitoring; Grafana reads Cloud
Monitoring as a datasource. The migration path is one config file when a second destination
appears — **TDR-008**.

## Affected modules
| Module | Role in this feature | Generated SPEC |
|--------|----------------------|----------------|
| **Project Service** *(new, `service/`)* | Go service on Cloud Run: `/v1/events`; owns the metric allowlist and the OTel export | SPEC-022 |
| **Cloud Monitoring** *(new integration)* | Where every metric lands; Grafana reads it | SPEC-022 |
| **TelemetryClient** *(new, app)* | Accumulates pending events, enforces the once-a-day rule, sends the batch, honours the switch and the gate | SPEC-023 |
| **OverlayPresenter** | Reports each Reminder animation played, and the new day with it | SPEC-023 |
| **AppDelegate** | Reports the installation on launch — first install or update — and the new day on launch and on wake | SPEC-023 |
| **AppCoordinator** | Builds the TelemetryClient from configuration, or does not | SPEC-023 |
| **MenuBar UI** | States that Telemetry is on and offers the switch; carries the first-launch notice | SPEC-023 |

New integrations: the Project Service, Cloud Monitoring and Grafana Cloud. No database, no
scheduler. `architecture.md` gains them in the same change.

## Interfaces / contract (source of truth)

**`POST /v1/events`** — sent when the pending batch is non-empty, at most hourly
```
{ "appVersion": "1.4.2",
  "macosMajor": "15",
  "events": [ { "name": "planes_flown",     "value": 3 },
              { "name": "daily_active", "value": 1 },
              { "name": "installation", "value": 1, "kind": "update" } ] }
→ 202 Accepted   (no body)
```

**Allowlist** — a name outside it is dropped, the rest of the batch still counts
```
planes_flown   counter · label app_version               · value 1..1000
daily_active   counter · labels app_version, macos_major  · value == 1
installation   counter · labels app_version, kind         · value == 1
                         kind ∈ { first_install, update }
```

Every request carries `X-Telemetry-Key: <build-time key>`; without it, 401 and nothing recorded.
**No request carries an identifier of any kind.**

**Metrics**
| Metric | Kind | Labels | Answers |
|---|---|---|---|
| `planes_flown_total` | counter | `app_version` | Airplanes per hour / per day |
| `daily_active_total` | counter | `app_version`, `macos_major` | Installs used that day, and on which version — read one bar per day |
| `installations_total` | counter | `app_version`, `kind` | Installations that ran at least once, split into first install and update |

**App-side configuration gate** — mirrors `UpdateConfiguration`
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
    func recordActiveToday()           // no-op when already sent for the current local day;
                                       // called on launch, on wake, on each animation, and on each timer tick
    func recordInstallationIfChanged() // first_install when no version was stored, update when it differs
}
```

## Affected domain model
- **Telemetry** *(new)* — a batch of named counter events. Counts and versions only, no identifier.
- **Project Service** *(new)* — the only project-owned server the app talks to besides the
  Release host.
- **Install** — still the unit being counted, but now counted **without being identified**: the
  app reports at most one "used today" event per Install per day and the service just sums.
- Unchanged: Account, Calendar, Event, Reminder, Trigger, Overlay. This design observes one
  existing occurrence (a Reminder animation played) and changes nothing about any of them.

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
- **No gauges, no database, no scheduled job.** Every number this design publishes is additive, so
  it can be produced from the request that reports it. Everything that required seeing the whole
  fleet at once was cut in §Analysis.
- **No identifier, anywhere.** Nothing to deduplicate server-side means nothing to store, and the
  privacy policy gets to say the reports contain no identifier at all.
- **"Used today" is deduped on the client, by local calendar day**, and checked on launch, on
  wake, on each animation and on each timer tick. A date comparison dedupes exactly; an
  elapsed-time rule drifts. Wake matters most: a menu bar agent rarely relaunches.
- **`daily_active_total` is read bucketed by day.** Summed over a longer window it is Install-days,
  not distinct Installs.
- **The pending batch is cleared only after a `202`.** An offline or sleeping Mac accumulates and
  reports late; an animation is never lost, only delayed.
- **Metric names come from a server-side allowlist.** A client that could invent a name could
  invent time series, and time series cost money.
- **One endpoint for every counter.** Adding a metric is an allowlist entry and a call site.
- **The test animation does not count**, and neither does a relaunch on the same day.
- **`--max-instances` is part of the design**, not an ops detail.
- **The service lives in `service/`, in this repository, public.** Nothing secret in it beyond
  environment variables. It does make the project multi-part; `conventions.md` §A.1 is updated in
  the same change.

## Out of scope / open questions
- **Out — retention, cohorts, 7/30-day actives, total Installs ever.** Cut deliberately; see
  §Analysis. They come back with subscriptions, which bring an identity of their own.
- **Out — Accounts and Calendars per Install.** Interesting once, not worth a field.
- **Out — crash reporting (RF-18).** Its own AYD; see §Goal.
- **Out — subscriptions, entitlements, feature locks, per-Install authentication.**
- **Out — logs and traces.** Counters only.
- **Known — every count is a lower bound.** Anyone who switches Telemetry off is invisible, and
  there is no honest way to correct for it. The dashboard should say so rather than pretend.
- **Known — `daily_active_total` is not unique users.** One person with two Macs counts twice; one
  Mac used by two people counts once. Stated on the dashboard.
