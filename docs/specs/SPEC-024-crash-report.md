---
id: SPEC-024
type: spec
status: draft
updated: 2026-09-16
parents: [AYD-012]
related: [SPEC-022, SPEC-023, RF-18, RNF-13, GLO, REQ-01]
---

# SPEC-024: Crash report with consent — what + how

> Implements RF-18: after an abnormal termination the app finds the crash report macOS itself
> wrote, shows the user what it contains, and sends it only if they agree. Depends on
> **SPEC-023** for the configuration gate and the HTTP boundary, and on **SPEC-022** for
> `/v1/crash`. Like every other report, it carries **no identifier**.

## What (goal)
1. On launch, find crash reports macOS wrote for this app since the last check.
2. Show the user the report's contents and ask — one decision per report, no standing permission.
3. Send only on agreement; remember which reports were already handled so the same crash is never
   offered twice.
4. No crash SDK and no in-process handler: macOS already writes a better report than a dying
   process can.

Out of scope: symbolication (done offline, from the release dSYM, when a report is actually being
read); grouping and alerting.

## Acceptance criteria
```gherkin
Scenario: A new crash report is offered
  Given macOS wrote a crash report for this app after the last check
  When the app launches
  Then the user is shown what the report contains and asked whether to send it

Scenario: Sending happens only on agreement
  Given the user declines
  Then nothing is sent
  And the report is marked handled and never offered again

Scenario: Agreement sends exactly one report
  Given the user agrees
  Then POST /v1/crash is sent once with that report
  And the report is marked handled

Scenario: A clean launch asks nothing
  Given there is no crash report newer than the last check
  Then the user is not prompted and no request is made

Scenario: A Source Build never offers it
  Given the build carries no Telemetry configuration
  Then no crash report is read and the user is never prompted

Scenario: Only this app's reports are read
  Given the crash report directory contains reports for other processes
  Then only reports whose process matches this app are considered
```

## How (approach)
- Scan `~/Library/Logs/DiagnosticReports/` for `.ips` files whose process name matches the app and
  whose modification date is after the persisted last-check timestamp.
- Present the report in a scrollable window with a plain explanation and Send / Don't send. The
  user sees the actual text before it leaves the Mac — that is the point of the design, and the
  reason no standing permission is offered.
- Handled reports are recorded by file name so nothing is offered twice, and the last-check
  timestamp advances regardless of the answer.
- The same configuration gate as SPEC-023: with no configuration, the scanner is never
  constructed.
- Retention is decided here because it is a privacy-policy fact, not an implementation detail:
  crash reports are kept **90 days** and then deleted, which the privacy policy states.

## Steps
1. `CrashReportScanner`: find candidates, filter by process and timestamp.
2. `CrashReportStore`: the handled set and the last-check timestamp in `UserDefaults`.
3. The consent window, shown at most once per launch, queued if several reports are pending.
4. Send through the Telemetry client's HTTP boundary, reusing `X-Telemetry-Key`; the payload
   carries the app and macOS versions and the report, and nothing else.
5. A lifecycle rule on the storage bucket that deletes reports after 90 days.
6. Privacy policy: what a crash report contains, that it is only sent on agreement, how long it
   is kept.

## Affected files
- `cal-reminder/Telemetry/CrashReportScanner.swift`, `CrashReportConsentWindow.swift` (new)
- `cal-reminder/App/AppCoordinator.swift`
- `docs/privacy-policy.md`

## Tests
- **Acceptance:** one test per Gherkin scenario, against a fake directory listing and a fake HTTP
  boundary.
- **Unit:** the process-name and timestamp filters; the handled set across restarts; the
  last-check timestamp advancing on a decline.

## Checklist
- [ ] Nothing is sent without an explicit per-report agreement
- [ ] Reports for other processes are never read
- [ ] The retention window is implemented and stated in the privacy policy
- [ ] The payload carries no identifier
