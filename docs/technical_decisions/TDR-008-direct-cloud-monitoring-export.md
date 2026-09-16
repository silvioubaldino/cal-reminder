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
AYD-012 puts every metric in Cloud Monitoring and reads it from Grafana Cloud as a datasource.
The sibling `personal-finance` project solves the same problem with an **OpenTelemetry Collector
running as a Cloud Run sidecar**: the service exports OTLP to `localhost:4318`, and the collector
routes by metric-name prefix — `biz_*` to Cloud Monitoring, everything else to Grafana Cloud —
with the Grafana credentials coming from Secret Manager. That pattern works, is versioned, and is
already understood by whoever maintains both projects.

Two facts decide whether to copy it here. First, this service has **one** metrics destination, not
two. Second, it handles a few requests per Install per day — the whole fleet is a trickle — and a
sidecar is a second container in the same Cloud Run service, paid for in memory and cold-start
time on every scale-from-zero.

There is also a constraint that any answer must satisfy: Cloud Monitoring rejects more than one
point per time series per 5 seconds and requires points in chronological order, so concurrent
Cloud Run instances must not write the same series. The Collector solves this with its
`resourcedetection` processor; whatever replaces it has to solve it too.

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
- **Collector sidecar from day one (copy `personal-finance`)** — rejected for now: it buys
  prefix-based routing to a second backend that does not exist here, and charges memory and cold
  start on a service whose traffic is a trickle. Adopted the moment there is a second destination.
- **Send to Grafana Cloud only, via OTLP** — rejected: the Grafana Cloud free tier keeps metrics
  for about two weeks, while RNF-13 asks for at least twelve months of history. Cloud Monitoring
  retains user-defined metrics for 24 months at no cost, so it is the system of record and Grafana
  is the viewer.
- **Write `projects.timeSeries.create` by hand** — rejected: it means owning cumulative start
  times and chronological ordering, which is exactly the class of bug the Google exporters have
  open issues about. The SDK already does it correctly.
- **Log-based metrics (structured logs plus a log-based metric)** — rejected: it stores a number
  as text so that it can be parsed back into a number, and it makes the metric definition live in
  a console rather than in the code.

## Consequences
- One exporter, no YAML, no second container; the whole metrics setup is one file in the service.
- Grafana depends on the Cloud Monitoring datasource being configured; losing that costs the
  dashboards, not the data.
- Adopting the sidecar later is a deployment change plus one config file, not a rewrite — the
  instrument definitions are unaffected.
