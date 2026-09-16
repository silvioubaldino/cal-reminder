---
id: TDR-008
type: tdr
title: Export metrics straight to Cloud Monitoring, without a Collector sidecar
status: proposed
updated: 2026-09-16
parents: [AYD-012]
related: [RNF-13, SPEC-022]
superseded_by: null
---

# TDR-008: Export metrics straight to Cloud Monitoring, without a Collector sidecar

> Append-only: never rewrite. A new decision = a new TDR that supersedes this one
> (`superseded_by`).

## Context
AYD-012 puts every metric in Cloud Monitoring and reads it from Grafana Cloud as a datasource —
one metrics destination, and a service handling a few requests per Install per day.

Any answer has to satisfy one constraint: Cloud Monitoring rejects more than one point per time
series per 5 seconds and requires points in chronological order, so concurrent Cloud Run instances
must not write the same series.

## Decision
The service exports **directly to Cloud Monitoring** from the OpenTelemetry Go SDK, with no
Collector and no OTLP hop:

- `go.opentelemetry.io/otel/sdk/metric` with a `PeriodicReader` on a 60 s interval and the Google
  Cloud Monitoring exporter.
- `go.opentelemetry.io/contrib/detectors/gcp` supplies the resource, which carries the Cloud Run
  instance identity — so each instance writes its own time series and the 5-second limit is
  satisfied by construction, the same property the Collector's `resourcedetection` provides.
- `ForceFlush` on `SIGTERM`, because Cloud Run freezes an instance as soon as it goes idle and a
  60-second reader would otherwise lose the batch.
- Grafana Cloud reads Cloud Monitoring as a datasource instead of receiving its own copy.

**Migration is explicit and cheap.** The moment a second destination or a second signal appears —
traces, logs, operational metrics split from product KPIs — the service switches its exporter to
OTLP over `localhost:4318` and the sidecar is added with `personal-finance`'s `config.yaml`
adapted. The SDK-side instrumentation does not change; only the exporter and the deployment do.

## Alternatives & trade-offs
- **Collector sidecar** (the pattern the sibling `personal-finance` project uses, routing by
  metric-name prefix to two backends) — deferred: a second container's memory and cold start buy
  routing to a destination that does not exist here. Adopted when one does.
- **Grafana Cloud as the only backend, via OTLP** — rejected: its free tier keeps metrics for about
  two weeks, and RNF-13 asks for at least twelve months. Cloud Monitoring retains user-defined
  metrics for 24 months at no cost.
- **Writing `projects.timeSeries.create` by hand** — rejected: it means owning cumulative start
  times and chronological ordering, which the SDK already does correctly.

## Consequences
- One exporter, no YAML, no second container; the whole metrics setup is one file in the service.
- Grafana depends on the Cloud Monitoring datasource being configured; losing that costs the
  dashboards, not the data.
- Adopting the sidecar later is a deployment change plus one config file, not a rewrite — the
  instrument definitions are unaffected.
