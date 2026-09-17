---
id: TDR-025
type: tdr
title: Label planes_flown with the Trigger's origin
status: accepted
updated: 2026-09-17
parents: [AYD-013]
related: [RF-17, RNF-13, RN-07, TDR-008@service]
superseded_by: null
---

# TDR-025: Label planes_flown with the Trigger's origin

> Append-only: never rewrite. A new decision = a new TDR that supersedes this one
> (`superseded_by`).

## Context
`AYD-013` counts every Reminder animation played as `planes_flown`, with no further breakdown.
Three different things fire a Trigger — an Event's own Reminder (RN-04/RN-06), an Extra Reminder
the user added (RF-15), and the menu bar's test animation — and the project cannot tell them
apart in the dashboard.

`AYD-013` already established `kind` as the mechanism for labelling a counter without widening
the allowlist's shape: `installation` uses it for `first_install`/`update`. Giving `planes_flown`
a `kind` too is the same mechanism applied to an existing counter, not a new endpoint, field, or
contract shape — so it is captured here rather than in a superseding AYD.

RN-07 makes an Event's effective Reminders the deduped union of its own Reminders and any Extra
Reminders; a minute produced by both must still get one label.

## Decision
1. **Three origins, reported as `planes_flown`'s `kind`:** `event_reminder` (the Event's own
   Reminder, RN-04/RN-06), `extra_reminder` (RF-15), `test_animation` (the menu bar's test).
2. **RN-07 collision rule:** a minute produced by both the Event's own Reminder and an Extra
   Reminder is tagged `event_reminder` — it would fire with or without the Extra Reminder, so
   that is its origin. Tagging happens in `ReminderResolver`, before the flat minute list used
   elsewhere is produced, so the union+dedup never has to reconstruct it after the fact.
3. **`kind` stays optional for `planes_flown`.** Unlike `installation`, an app build that predates
   this label still reports `planes_flown` with no `kind`; the service keeps counting it
   unlabeled instead of dropping it. This is what makes either deploy order (server allowlist
   first, or app release first) non-destructive.
4. **The test animation now reports Telemetry at all.** It previously reported nothing —
   `AppCoordinator.testAnimation()` had no hook into `TelemetryClient`. It gets one, mirroring
   the existing `onWake` pattern, so `test_animation` counts show up without coupling
   `AppCoordinator` to `TelemetryClient` directly.

## Alternatives & trade-offs
- **A new metric name per origin** (e.g. `planes_flown_extra`) — rejected: three time series to
  read together instead of one filtered by label, for a distinction that is exactly what `kind`
  already exists to express.
- **Require `kind` on `planes_flown`, like `installation`** — rejected: it would drop every
  pre-this-feature app build's animations the moment the server allowlist ships, before those
  builds have had a chance to update.
- **Attribute a colliding minute to `extra_reminder` instead** — rejected: the Extra Reminder is
  never the reason that minute fires (RN-07's fallback still applies to the Event's own branch
  independently), so crediting it would overstate how often Extra Reminders matter.

## Consequences
- `Trigger` gains an `origin` field (default `.eventReminder`, so existing call sites are
  unaffected); `TelemetryPendingBatch.planesFlown` becomes keyed by origin instead of a scalar,
  to survive a failed send holding flights of more than one origin at once.
- The service's `planes_flown` allowlist entry gains three recognized kinds and stays
  non-required, mirroring `installation`'s required one.
- The dashboard can split `planes_flown_total` by `kind` without a new time series.
