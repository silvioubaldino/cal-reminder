---
id: CHANGELOG
type: changelog
title: Changelog
status: approved
updated: 2026-09-10
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

-

## Release - v0.2.2 - 10-09-2026

- Fixed: the app opened saying it could not check for updates at all — the previous release shipped the update helper in the wrong place, which stops the updater before it starts; a release that misplaces it can no longer be published.

## Release - v0.2.1 - 10-09-2026

- Fixed: an update was found and downloaded but never installed, failing at the last step — the app shipped without a helper its own security sandbox requires in order to run the installer; a release missing that helper can no longer be published.

## Release - v0.2.0 - 10-09-2026

- Implemented SPEC-021: fixed three ways a reminder could go silently missing — an event scheduled beyond the app's sync window, everything still pending when the Mac woke or an account was signed out, and a single deleted event that quietly stopped a calendar from syncing at all.

## Release - v0.1.0 - 10-09-2026

- Designed AYD-011 and wrote SPEC-021: a plan to fix three cases where an Event was silently never announced — one scheduled beyond the window the app first looked at, everything still pending being dropped whenever the Mac woke or an account was signed out, and a single deleted Event quietly stopping a calendar from syncing at all.
- Fixed: a published Release was built without its update feed settings, leaving it unable to update anyone; the release now carries them and refuses to publish if they are missing.
- Implemented SPEC-020: the app now checks for and installs updates on its own — a version row, a "Check for updates…" action, and a "Check automatically" toggle (off until the user opts in) in a Distributed Build; a Source Build states plainly that it has no updater and makes no request to any feed.
- Implemented SPEC-019: pushing a version tag now builds, signs, notarizes and publishes the app as a downloadable disk image with a signed update feed, refusing to publish anything that fails verification.
- Licensed the repository under PolyForm Shield 1.0.0: free to clone, build and use for any purpose, but not to redistribute as a competing product (RNF-12).
- Implemented SPEC-018: the app's Google client credentials are no longer in the repository — a fresh clone builds and runs with no credential at all, the menu says so and links to the setup guide instead of failing silently, and a configured build behaves exactly as before.
- Wrote SPEC-019 and SPEC-020: implementation plan for cutting a release — a signed, notarized disk image built from a tag — and for the app checking that feed and updating itself, with a build from source keeping no updater at all.
- Wrote SPEC-018: implementation plan for taking the app's Google credentials out of the repository and making a build from source a documented, working path — a fresh clone builds with no credential and the app says what it needs instead of failing silently.
- Revoked the Mac App Store as the distribution target and replaced it with direct distribution plus self-updating: the app will be downloaded as a signed, notarized disk image or installed with Homebrew, and will check for and install new versions on its own from a feed only the project can sign (AYD-009 and AYD-010, superseding AYD-003 and AYD-005; RF-16, RNF-07, RNF-11, TDR-006).
- Stated the distribution model in the requirements: the app is source-available and sold on trust — anyone can build and run it for free with their own Google credentials, and what a purchase buys is the ready-to-run, auto-updating build, with no licence key or feature gate anywhere in the app (RNF-12).
- Decided that the app's Google credentials must be rotated and injected at build time instead of living in the repository, now that the source is meant to be public (TDR-007, superseding TDR-003; RNF-10).
- Fixed: changing which calendars you're alerted on could drop the upcoming reminders of the calendars that stayed selected, until the next event edit; the list is now rebuilt in full when the selection changes.
- Implemented SPEC-017: a new "Reminders" menu lets you choose which alerts fly — the event's own ones, plus any of at-start/1/5/10/15 minutes before, in any combination; the menu states the current choice at a glance, warns when nothing is selected, and the upcoming reminders are rebuilt the moment you change it.
- Designed AYD-008 and added RF-15: choosing which reminders fire — the event's own ones plus a set of extra alerts the app adds to every event — with the Extra Reminder glossary term and the rule that combines both (RN-07).
- Implemented SPEC-016: the menu bar now has an "Accounts" submenu — one entry per connected Google Account, each with its own Calendars, Reconnect, and Sign out, plus "Add Google account…" to connect another one; an Account needing reconnection is marked in the menu.
- Implemented SPEC-015: the app now supports connecting more than one Google Account at once under the hood — each with its own Keychain-stored token and Calendar selection, polled independently so one Account's failure never affects the others; the existing single connected Account migrates over automatically. The menu bar still shows a single Account for now (SPEC-016 adds the "Accounts" menu).
- Wrote SPEC-015 and SPEC-016: implementation plan for connecting more than one Google Account at the same time, each with its own Calendars selection and an "Accounts" menu.
- Designed AYD-007: connecting more than one Google Account at the same time, each with its own Calendar selection; superseded AYD-002 (single-account Calendar selection) and added RF-14, the Account glossary term, and a technical decision on account identity and storage scoping (TDR-005).
- Fixed the banner's tone on wide-gamut displays: a calendar's color is now drawn in the screen's own color space, so it matches the shade shown in Google Calendar instead of coming out oversaturated (TDR-004).
- Implemented SPEC-014: each banner is now painted with the color of the calendar its event came from, with a "Match calendar color" toggle in the menu that falls back to the chosen color preset.
- Designed AYD-006 and added RF-13: painting the banner with the calendar's own color, keeping the color preset as the fallback.
- "Refresh now" now does a full resync: it refetches the whole upcoming window and rebuilds the reminder list, so entries for events that were deleted or rescheduled disappear.
- The Banner now shows the Event's title (bold) and its time (italic) on two centered lines, and widens on demand for a long title instead of hiding part of it (RF-05).
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
