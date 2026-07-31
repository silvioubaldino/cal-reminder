---
id: CHANGELOG
type: changelog
title: Changelog
status: approved
updated: 2026-07-16
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

- Implemented SPEC-012: the menu bar's "Refresh now" is now always clickable, not only when there's no upcoming Reminder, so a stale sync can always be corrected manually.
- Fixed the Banner's text overflowing and hiding part of a long Event title; it now wraps onto extra lines instead (SPEC-001).
- Implemented SPEC-011: added a "Click anywhere to skip" menu toggle to opt out of skipping a Reminder animation, persisted across restarts.
- Implemented SPEC-010: the menu now only shows "Connected" when the session is actually verified (not just when a token is stored), a revoked Google session prompts reconnecting instead of silently staying stuck, the empty "No upcoming reminders" row can trigger a manual Poll, background Poll runs every 5 minutes instead of 2, and the menu offers a "Sign out of Google" action.
- Fixed the menu bar's "Next" Reminder display going stale to "No upcoming reminders" after an incremental Poll reported no changed Events, even though a Trigger was still correctly armed.
- Reframed the project scope from "personal, local-use" to a distributed, commercial product, and added RNF-10: the app's OAuth client secret should live behind an app-owned token broker rather than embedded in the shipped binary (planned; the interim embedded-secret state stays documented in TDR-003).
- Fixed Google sign-in: the embedded OAuth client now sends the client secret Google requires for installed apps, so connecting actually completes and the account email, Calendars, and next Event appear (TDR-003 supersedes TDR-002).
- Implemented SPEC-006: Events with no popup Reminder configured now get a default 5-minutes-before alert; Events that already have one keep only their own.
- Implemented SPEC-009: replaced the per-user, on-disk Google OAuth credentials with a single embedded public client, so the app no longer needs a manually-created credentials file to connect, needed for App Review.
- Implemented SPEC-008: App Sandbox entitlements, a privacy manifest, a full app icon, real bundle metadata, and a public privacy policy, needed for the Mac App Store.
- Implemented SPEC-007: a CI gate that builds, tests, and lints (SwiftLint) every push and pull request, blocking the merge on failure.
- Designed AYD-005: App Sandbox and privacy compliance artifacts (entitlements, privacy manifest, app icon, bundle metadata, privacy policy) needed for the Mac App Store.
- Designed AYD-004: an automated CI gate that builds, tests, and lints every push and pull request.
- Designed AYD-003: making the app distributable through the Mac App Store, rearchitecting Google sign-in so it works sandboxed and can be reviewed without manual credentials.
- Scoped App Store readiness as post-MVP requirements (RNF-07 distribution, RNF-08 privacy compliance, RNF-09 quality gate).
- Implemented SPEC-005: the menu now lists every Calendar in the connected account with a checkbox to choose which ones generate Reminders, persisted across restarts.
- Wrote SPEC-005: implementation plan for the Calendar-selection menu (list Calendars, multi-select which to alert on, per-Calendar Poll, persisted).
- Designed AYD-002: reading every Calendar in the connected account and letting the user pick, from the menu bar, which Calendars to be alerted on (default: all); added the Calendar glossary term and RF-10.
- Fixed: Reminders were not being detected due to a broken API call; now reading defaults from the calendar events list.
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
