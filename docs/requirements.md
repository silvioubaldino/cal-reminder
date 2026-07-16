---
id: REQ-01
type: requirements
title: Requirements and glossary
status: approved
updated: 2026-07-16
parents: []
children: [AYD-001, AYD-003, AYD-004, AYD-005]
related: [GLO]
---

# Requirements

> macOS app that connects to Google Calendar and flies an airplane pulling a banner across
> the screen at each event's reminder time. It is built to be **distributed** (Mac App Store)
> and **sold** — a commercial product, not a personal/local-only tool. Keep it lean, but hold
> it to a distributable bar on security and privacy (RNF-05, RNF-08, RNF-10).

## Functional (RF)
| ID | Requirement | Priority | Acceptance criterion |
|----|-------------|----------|----------------------|
| RF-01 | Connect to Google Calendar (read-only) via OAuth, once | Must | The user authorizes once in the browser; the app stays connected across restarts without re-authorizing |
| RF-02 | Read timed Events from each selected Calendar | Must | Events with a start time are read from every selected Calendar (RF-10); all-day Events are ignored (RN-01) |
| RF-03 | Resolve each Event's effective popup Reminders | Must | For each Event, the app derives its Reminders from `overrides` or the calendar defaults, keeping only `popup` (RN-04) |
| RF-04 | Fly the airplane + banner Overlay at each Reminder time | Must | At `Event start − Reminder minutes`, an airplane pulling a banner slides across the screen over all windows (RN-02) |
| RF-05 | The banner shows the Event and time | Must | The banner text reads `<Title> at HH:MM (in X min)` |
| RF-06 | Menu bar control | Must | From the menu bar the user can see connection status (including the connected account's email), toggle the app on/off, test the animation, reconnect Google, choose the Airplane's Flight Speed, choose the Banner's color, choose which Calendars to be alerted on (RF-10), and quit |
| RF-07 | Choose the Airplane's Flight Speed | Must | The menu bar offers 3 Flight Speed presets (Slow/Normal/Fast); the selection persists across restarts, applies from the next animation on, and the Airplane crosses any screen size at the same visual speed |
| RF-08 | Choose the Banner's color | Must | The menu bar offers a set of Banner color presets; the selection persists across restarts and applies from the next animation on |
| RF-09 | Skip a playing Reminder animation | Should | While the airplane + banner Overlay is flying, a click anywhere on the screen accelerates it to cover the remaining distance in ~1.5s instead of blocking the click through |
| RF-10 | Choose which Calendars to be alerted on | Should | The menu bar lists every Calendar in the connected account with a multi-select control; only selected Calendars generate Triggers; the selection persists across restarts and applies from the next Poll on. Default when the user has not chosen: all Calendars |

## Non-functional (RNF)
| ID | Category | Requirement | Target |
|----|----------|-------------|--------|
| RNF-01 | Footprint | Runs as a background menu bar agent | `LSUIElement` app, no Dock icon |
| RNF-02 | Overlay behavior | The Overlay never steals focus, and appears above everything; it is click-through except while a Reminder animation is playing, when a click skips it (RF-09) | Shows over fullscreen apps and all Spaces; clicks pass through to the window below when idle; never activates the app or takes key focus, even mid-flight |
| RNF-03 | Precision | The Trigger fires close to the computed time | Error < 5 s from the computed fire time |
| RNF-04 | Resilience | Tolerant to sleep/wake and network loss | Re-syncs on wake; keeps scheduled Triggers across transient network failures |
| RNF-05 | Security | The **user's** secrets are stored securely | The connected account's OAuth access/refresh tokens live only in the macOS Keychain, never in plaintext on disk |
| RNF-06 | Network | Efficient calendar sync | Incremental poll using `syncToken` |
| RNF-07 | Distribution | Distributable through the Mac App Store, and testable by App Review | App Sandbox enabled and signed with a real Team; App Review can connect and exercise the app with a demo Google account, without creating any Google Cloud credentials (AYD-003) |
| RNF-08 | Privacy compliance | Declares data collection/use to Apple and Google | Ships a privacy manifest (`PrivacyInfo.xcprivacy`) and a public privacy-policy URL; the `calendar.readonly` restricted scope passes Google verification (AYD-005) |
| RNF-09 | Quality gate | Every change is built, tested, and linted automatically | CI builds the app, runs the test suite, and lints the sources on each push/PR; a failure blocks the merge (AYD-004) |
| RNF-10 | Security (app credential) | The **app's** OAuth client secret is not exposed in the distributed binary | Target: the OAuth token exchange/refresh runs behind an app-owned backend (token broker) so the client secret ships only on the server; the app authenticates to that backend instead of carrying the secret. Planned, not yet built — the interim embedded-secret state is documented in TDR-003 (AYD-003) |

## Business rules
- RN-01: Only timed Events generate Triggers; all-day Events are ignored.
- RN-02: A Trigger fires at `Event start − Reminder minutes`, one per popup Reminder of the Event.
- RN-03: The same Reminder never fires twice (dedupe by `calendarId#eventId#minutes`).
- RN-04: If `reminders.useDefault` is true, use the calendar's default Reminders; otherwise use `reminders.overrides`, keeping only `method == popup`.
- RN-05: Overlapping Triggers are queued — one animation plays at a time (FIFO).
- RN-06: If an Event's resolved popup Reminders (RN-04) are empty, add a single 5-minutes-before Reminder; otherwise use the resolved set unchanged.

## MVP scope
- **In:** Google OAuth connect (read-only, including the account's email for display) with Keychain-stored token; reading timed Events from the selected Calendars of the connected account; choosing which Calendars to be alerted on (RF-10); resolving popup Reminders; airplane + banner Overlay over all windows; menu bar control (status incl. connected email, on/off, test, reconnect, Flight Speed, Banner color, Calendar selection, quit); queueing overlapping animations.
- **Out (for now):** actions on the Event (open Meet/Zoom link); rich settings UI beyond Flight Speed, Banner color, and Calendar selection presets (e.g. custom colors, banner size); multiple Google accounts; all-day Events; multi-monitor targeting beyond the main screen.

## Post-MVP: App Store readiness (planned)
The app is intended for **public distribution and eventual sale**, so App Store readiness and a
distributable security posture are in scope (not yet all built), across independent AYDs so each
has a defined boundary: **AYD-003** (Mac App Store distribution & OAuth rearchitecture — RNF-07),
**AYD-005** (App Sandbox & privacy compliance artifacts — RNF-08), and **AYD-004** (CI &
code-quality gate — RNF-09). AYD-004 can land on its own; AYD-003 depends on the entitlements
defined in AYD-005.

Because the app is distributed rather than personal, the OAuth **client secret** must not remain
embedded in the shipped binary: hardening it behind an app-owned token broker is now a target
(**RNF-10**, owned by AYD-003). The current embedded-secret build (TDR-003) is the interim state
that makes sign-in work today; RNF-10 is the direction, to be realized by a future TDR — it does
not retract TDR-003, it succeeds it.

---

# Glossary (ubiquitous language) — GLO

<!--
id: GLO / type: glossary
Canonical domain definitions. Docs and code use these terms.
Rule: add the term here BEFORE using it. List synonyms to avoid — that's where
ambiguity turns into a bug.
-->

| Term (EN) | Definition | Synonyms to avoid |
|-----------|------------|-------------------|
| Calendar | _A Google Calendar in the connected account (the `primary` one or a secondary/subscribed one). The user selects which Calendars generate Triggers (RF-10)._ | "agenda", "list" |
| Event | _A Google Calendar entry with a start time (timed); all-day entries are out of scope._ | "meeting", "appointment" |
| Reminder | _A `popup` notification configured on an Event, expressed as minutes before its start._ | "notification", "alert" |
| Trigger | _The computed moment to fire the animation: `Event start − Reminder minutes`._ | "alarm", "job" |
| Overlay | _The transparent, always-on-top window that draws the animation; click-through except while flying, when a click skips it (RF-09)._ | "popup", "window" |
| Airplane | _The little plane that flies across the Overlay pulling the banner._ | "plane sprite" |
| Banner | _The strip pulled by the Airplane, showing the Event text._ | "faixa", "ribbon", "label" |
| Poll | _The periodic fetch of upcoming Events from the Google Calendar API._ | "sync", "refresh" |
| Flight Speed | _The animation-speed preset (Slow/Normal/Fast) controlling how fast the Airplane crosses the Overlay; user-selectable from the menu bar and persisted across restarts._ | "animation speed", "duration" |
