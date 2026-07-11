---
id: CHANGELOG
type: changelog
title: Changelog
status: approved
updated: 2026-07-11
---

# Changelog

Changes to the docs (requirements, glossary, architecture, design/AYD, conventions) and
to the app. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

**Policy**:

- **Order:** most recent on top; new entries go **above** the previous ones.
- **Unreleased:** unreleased work accrues under `## Unreleased` (always the top block),
  with no date/version. On a release, `## Unreleased` becomes `## [dd-MM-yyyy - vX.Y.Z]`
  and a new empty `## Unreleased` is opened above it.
- **One line per PR:** each PR adds a **single line** summarizing what it delivers —
  general, no implementation detail (that lives in the SPEC/TDR/PR). See CONV §B.3.

## Unreleased

- Moved the flight path to the screen's top third, shrank and centered the Banner text, and made a playing Reminder animation skippable with a click (accelerates to the end in ~1.5s).
- Made Flight Speed independent of screen size, sped up all 3 presets, drew a rope tying the Airplane to the Banner, added a configurable Banner color to the menu, and show the connected Google account's email in the menu bar status.
- Implemented SPEC-003: precise per-Trigger scheduling with dedupe and sleep/wake resilience, and real menu bar status, on/off, and reconnect control.
- Implemented SPEC-002: Google Calendar OAuth connection and reading upcoming Events into Triggers with their popup Reminders resolved.
- Implemented SPEC-004: a "Flight Speed" menu with 3 presets (Slow/Normal/Fast), persisted across restarts.
- Scaffolded the macOS menu bar app project and implemented SPEC-001: the airplane + banner Overlay with a FIFO queue and a "Test animation" menu action.
- Wrote the implementation specs for AYD-001: SPEC-001 (overlay airplane + banner), SPEC-002 (Google auth + calendar poll), SPEC-003 (scheduler + menu bar control).
- Filled REQ-01 (functional/non-functional requirements, business rules, MVP scope) and the glossary (Event, Reminder, Trigger, Overlay, Airplane, Banner, Poll).
- Filled the living architecture (ARCH): container view and the app's component breakdown.
- Migrated the original AyD into the framework as AYD-001 (airplane event reminders), the source of the design; linked to REQ-01.
- Bootstrapped the single-part SDD docs framework (conventions, requirements/architecture skeletons, AYD/SPEC/TDR templates).
