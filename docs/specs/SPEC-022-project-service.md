---
id: SPEC-022
type: spec
status: draft
updated: 2026-09-16
parents: [AYD-012]
related: [TDR-008, RNF-13, RF-17, GLO, REQ-01]
---

# SPEC-022: Project Service — event ingestion — what + how

> Implements the backend half of AYD-012: a Go service on Cloud Run that accepts a batch of
> allowlisted counter events and publishes each one to Cloud Monitoring.
> No database and no scheduled job — everything it publishes is additive. Nothing in the app
> changes here; **SPEC-023** is what starts talking to it.

## What (goal)
1. `POST /v1/events` accepts the batch AYD-012 defines, authenticated by the build-time key, and
   increments one counter per allowlisted event.
2. A name outside the allowlist, or a value outside its range, is dropped without failing the
   batch or the request.
3. Every metric is published to Cloud Monitoring per TDR-008 and visible on a Grafana dashboard.
4. The service cannot run up a bill under flood.

Out of scope: the app-side client (SPEC-023); crash reporting, which AYD-012 takes out of scope
entirely; anything to do with subscriptions.

## Acceptance criteria
```gherkin
Scenario: A batch increments one counter per event
  Given a valid X-Telemetry-Key
  When POST /v1/events arrives with planes_flown 3, daily_active 1 and installation kind update
  Then the response is 202
  And planes_flown_total increases by 3 for that app_version
  And daily_active_total increases by 1 for that app_version and macos_major
  And installations_total increases by 1 for that app_version and kind

Scenario: An unknown metric name is dropped, the rest of the batch survives
  Given a batch carrying planes_flown 2 and a name that is not in the allowlist
  Then the response is 202
  And planes_flown_total increases by 2
  And no time series is created for the unknown name

Scenario: An out-of-range value is dropped
  Given a batch carrying planes_flown 100000, or daily_active 7, or a negative value
  Then that event is dropped and no counter moves for it
  And the response is still 202

Scenario: An installation event with an unknown kind is dropped
  Given an installation event whose kind is neither first_install nor update
  Then that event is dropped and installations_total does not move

Scenario: A request without the key is rejected
  Given X-Telemetry-Key is absent or wrong
  When any endpoint is called
  Then the response is 401 and no metric is published

Scenario: A malformed app version never becomes a label
  Given appVersion does not match the expected version pattern
  Then the request is rejected with 400 and no time series is created

Scenario: An oversized body is refused before it is read
  Given a body larger than the configured maximum
  Then the response is 413 and the body is not buffered

Scenario: A batch with too many events is refused
  Given more events than the configured maximum
  Then the response is 413

Scenario: Metrics survive the instance being frozen
  Given the service receives SIGTERM
  Then the meter provider is flushed before the process exits

Scenario: No request carries an identifier
  Given any accepted payload
  Then it contains no install, device, user or session identifier
  And nothing identifying is written to the service's logs
```

## How (approach)
- **One Go service, `service/`**, standard library routing; handlers validate and increment,
  nothing else. No persistence layer at all.
- **The allowlist is a table in code** — name, permitted label set, permitted value range — and it
  is the only thing that decides whether an event becomes a time series.
- **Metrics via the OTel SDK straight to Cloud Monitoring** (TDR-008): `PeriodicReader` at 60 s,
  `contrib/detectors/gcp` for the resource so each Cloud Run instance writes its own series, and
  `ForceFlush` on `SIGTERM`.
- **Answer first, record after**: `/v1/events` answers `202` and does its work on a
  context detached from the request, the way `personal-finance` does it. Telemetry must never
  surface as a 4xx because of one bad event.
- **Client IPs are excluded from the service's logs**, so "we do not keep the IP" is true rather
  than aspirational.

## Steps
1. `service/` skeleton: `main.go`, config from the environment, `/healthz`, graceful shutdown with
   a metrics flush on `SIGTERM`.
2. Metrics package: meter provider per TDR-008 and the three counters from AYD-012's table.
3. The allowlist table and its validator.
4. `/v1/events` with the key middleware, the size and batch limits, and the validator.
5. Deploy workflow, triggered only on `service/**`: build, deploy to Cloud Run with
   `--max-instances` set, Workload Identity Federation instead of a service-account key.
6. Log exclusion for client IPs; a per-IP rate limit in front of the handlers.
7. Grafana dashboard on the Cloud Monitoring datasource: airplanes per day, Installs used per day
   by version (**one bar per day**, never summed over the selected range), and installations split
   by kind — with a note that every count is a lower bound and that `daily_active_total` is not
   unique users.
8. A budget alert on the project.

## Affected files
- `service/` — the whole service (new)
- `.github/workflows/deploy-service.yml` (new)
- `docs/architecture.md`

## Tests
- **Acceptance:** one test per Gherkin scenario, with the metric recorder faked at the boundary.
- **Unit:** the allowlist validator — unknown name, unknown `kind`, value below and above each
  range, bad `appVersion` pattern, label set enforcement.
- **Not mocked:** the validator itself, which is the part that protects the bill.

## Checklist
- [ ] No payload and no log line carries an identifier
- [ ] An unknown metric name can never create a time series
- [ ] `--max-instances` set, budget alert configured
- [ ] Dashboard buckets `daily_active_total` by day and states that counts are lower bounds and
      not unique users
