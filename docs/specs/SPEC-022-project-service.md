---
id: SPEC-022
type: spec
status: draft
updated: 2026-09-16
parents: [AYD-012]
related: [TDR-008, RNF-13, RF-17, RF-18, GLO, REQ-01]
---

# SPEC-022: Project Service — ingestion, state and rollup — what + how

> Implements the backend half of AYD-012: a Go service on Cloud Run that accepts the app's two
> report shapes plus crash reports, keeps one Firestore document per Install, and publishes every
> metric to Cloud Monitoring. Nothing in the app changes here — **SPEC-023** is what starts
> talking to it, and until then the service is exercised by its own tests and by `curl`.

## What (goal)
1. `POST /v1/events`, `POST /v1/state` and `POST /v1/crash` accept the payloads AYD-012 defines,
   authenticated by the build-time key.
2. `installs/{installId}` in Firestore holds each Install's current state; `lastSeen` is written
   by `/v1/state` only.
3. `POST /internal/rollup`, reachable only by Cloud Scheduler with OIDC, recomputes the fleet
   gauges once a day.
4. Every metric in AYD-012's table is published to Cloud Monitoring, per TDR-008, and visible on a
   Grafana dashboard.
5. The service is deployed from this repository with a capped instance count and cannot run up a
   bill under flood.

Out of scope: the app-side client (SPEC-023), crash symbolication and the crash retention window
(SPEC-024), anything to do with subscriptions.

## Acceptance criteria
```gherkin
Scenario: An events report increments the counter and touches nothing else
  Given a valid X-Telemetry-Key
  When POST /v1/events arrives with planesFlown 3
  Then the response is 202
  And planes_flown_total increases by 3 for that app_version
  And no Firestore document is created or modified

Scenario: A state report writes the Install and publishes its samples
  Given a valid X-Telemetry-Key
  When POST /v1/state arrives for an installId that has never been seen
  Then installs/{installId} is created with firstSeen and lastSeen set to now
  And accounts_per_install and calendars_per_install each record one sample
  And no fleet total is published from the request

Scenario: A repeated state report updates without resetting firstSeen
  Given installs/{installId} already exists
  When POST /v1/state arrives again for it
  Then lastSeen, appVersion, macosVersion, accounts and calendarsSelected are overwritten
  And firstSeen keeps its original value

Scenario: A request without the key is rejected
  Given X-Telemetry-Key is absent or wrong
  When any /v1/ endpoint is called
  Then the response is 401
  And no metric is published and no document is written

Scenario: A malformed or out-of-range payload never 500s
  Given a body with accounts set to 9999999 or to a negative number
  When POST /v1/state arrives
  Then the response is 400
  And nothing is recorded

Scenario: An oversized body is refused before it is read
  Given a body larger than the configured maximum
  Then the response is 413 and the body is not buffered

Scenario: The rollup publishes the fleet gauges
  Given 5 Installs exist, 3 of them with lastSeen inside the last 24 hours
  When POST /internal/rollup runs
  Then installs_total is 5 and installs_active_1d is 3
  And installs_by_version carries one series per distinct appVersion
  And accounts_connected_total is the sum of every Install's accounts

Scenario: The rollup is not publicly reachable
  Given a request to /internal/rollup without a valid OIDC token
  Then the response is 403 and nothing is computed

Scenario: Metrics survive the instance being frozen
  Given the rollup handler has recorded its gauges
  When the response is written
  Then the meter provider has been flushed before the handler returns

Scenario: A crash report is stored and counted
  Given a valid X-Telemetry-Key
  When POST /v1/crash arrives with a report body
  Then the response is 202
  And the report is stored under the Install's prefix
  And crash_reports_total increases for that app_version
```

## How (approach)
- **One Go service, `service/`**, routed by the standard library or a thin router; handlers are
  free of business logic beyond validation, with Firestore and the metric recorder behind small
  interfaces so the tests do not need either.
- **Metrics via the OTel SDK straight to Cloud Monitoring** (TDR-008): `PeriodicReader` at 60 s,
  `contrib/detectors/gcp` for the resource, `ForceFlush` on `SIGTERM` and at the end of the
  rollup handler.
- **Firestore writes are idempotent**: a merge write for the mutable fields, `firstSeen` set only
  on creation, `planesTotal` via `firestore.Increment`.
- **Validation is defensive**: every numeric field has a permitted range, unknown fields are
  dropped, `installId` must look like a UUID, and `appVersion` is matched against a version
  pattern before it is allowed to become a metric label — a label is the one place a bad client
  can cost real money.
- **Answer first, record after** where it is safe: `/v1/events` and `/v1/crash` answer `202` and
  do their work on a context detached from the request, the way `personal-finance` does it.
  `/v1/state` answers after its write, because its response will later carry entitlements.

## Steps
1. `service/` skeleton: `main.go`, config from the environment, `/healthz`, graceful shutdown with
   a metrics flush on `SIGTERM`.
2. Metrics package: meter provider per TDR-008, plus the instrument set from AYD-012's table.
3. Firestore package: `InstallStore` with `UpsertState`, `IncrementPlanes` and `All`.
4. Handlers `/v1/events`, `/v1/state`, `/v1/crash`, with the key middleware, the size limit and
   the validation rules.
5. `/internal/rollup`: read the collection, compute the gauges, record them, flush, answer.
6. Crash storage: write the raw report to Cloud Storage under `crash/{installId}/{timestamp}.ips`.
7. Deploy workflow, triggered only on `service/**`: build, deploy to Cloud Run with
   `--max-instances` set and Workload Identity Federation instead of a service-account key.
8. Cloud Scheduler job, OIDC-authenticated against a dedicated invoker service account, daily.
9. Grafana Cloud dashboard reading the Cloud Monitoring datasource, one panel per metric in
   AYD-012's table.
10. A budget alert on the project.

## Affected files
- `service/` — the whole service (new)
- `.github/workflows/deploy-service.yml` (new)
- `docs/architecture.md` — Project Service, Firestore, Cloud Monitoring, Grafana

## Tests
- **Acceptance:** one test per Gherkin scenario, against the handlers with Firestore and the
  metric recorder faked at the boundary.
- **Unit:** the validation table (ranges, `installId` shape, `appVersion` pattern); `firstSeen`
  preserved across repeated state reports; the rollup's arithmetic over a fixture fleet, including
  an Install whose `lastSeen` is just inside and just outside each window.
- **Not mocked:** the rollup's aggregation logic itself, which is the part worth testing.

## Checklist
- [ ] `/v1/events`, `/v1/state`, `/v1/crash` and `/internal/rollup` behave as specified
- [ ] `installId` appears in no metric label anywhere
- [ ] Client IPs are excluded from the service's logs
- [ ] `--max-instances` set, budget alert configured
- [ ] Grafana dashboard live, with a note that Telemetry can be switched off so every count is a
      lower bound
