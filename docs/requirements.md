---
id: REQ-01
type: requirements
title: Requirements and glossary
status: approved
updated: 2026-07-11
parents: []
children: [AYD-001]
related: [GLO]
---

# Requirements

> Personal, local-use macOS app that connects to Google Calendar and flies an airplane
> pulling a banner across the screen at each event's reminder time. Keep it lean.

## Functional (RF)
| ID | Requirement | Priority | Acceptance criterion |
|----|-------------|----------|----------------------|
| RF-01 | Connect to Google Calendar (read-only) via OAuth, once | Must | The user authorizes once in the browser; the app stays connected across restarts without re-authorizing |
| RF-02 | Read timed Events from the primary calendar | Must | Events with a start time are read; all-day Events are ignored (RN-01) |
| RF-03 | Resolve each Event's effective popup Reminders | Must | For each Event, the app derives its Reminders from `overrides` or the calendar defaults, keeping only `popup` (RN-04) |
| RF-04 | Fly the airplane + banner Overlay at each Reminder time | Must | At `Event start − Reminder minutes`, an airplane pulling a banner slides across the screen over all windows (RN-02) |
| RF-05 | The banner shows the Event and time | Must | The banner text reads `<Title> at HH:MM (in X min)` |
| RF-06 | Menu bar control | Must | From the menu bar the user can see connection status (including the connected account's email), toggle the app on/off, test the animation, reconnect Google, choose the Airplane's Flight Speed, choose the Banner's color, and quit |
| RF-07 | Choose the Airplane's Flight Speed | Must | The menu bar offers 3 Flight Speed presets (Slow/Normal/Fast); the selection persists across restarts, applies from the next animation on, and the Airplane crosses any screen size at the same visual speed |
| RF-08 | Choose the Banner's color | Must | The menu bar offers a set of Banner color presets; the selection persists across restarts and applies from the next animation on |
| RF-09 | Skip a playing Reminder animation | Should | While the airplane + banner Overlay is flying, a click anywhere on the screen accelerates it to cover the remaining distance in ~1.5s instead of blocking the click through |

## Non-functional (RNF)
| ID | Category | Requirement | Target |
|----|----------|-------------|--------|
| RNF-01 | Footprint | Runs as a background menu bar agent | `LSUIElement` app, no Dock icon |
| RNF-02 | Overlay behavior | The Overlay never steals focus, and appears above everything; it is click-through except while a Reminder animation is playing, when a click skips it (RF-09) | Shows over fullscreen apps and all Spaces; clicks pass through to the window below when idle; never activates the app or takes key focus, even mid-flight |
| RNF-03 | Precision | The Trigger fires close to the computed time | Error < 5 s from the computed fire time |
| RNF-04 | Resilience | Tolerant to sleep/wake and network loss | Re-syncs on wake; keeps scheduled Triggers across transient network failures |
| RNF-05 | Security | Secrets are stored securely | Tokens only in the macOS Keychain, never in plaintext on disk |
| RNF-06 | Network | Efficient calendar sync | Incremental poll using `syncToken` |

## Business rules
- RN-01: Only timed Events generate Triggers; all-day Events are ignored.
- RN-02: A Trigger fires at `Event start − Reminder minutes`, one per popup Reminder of the Event.
- RN-03: The same Reminder never fires twice (dedupe by `eventId#minutes`).
- RN-04: If `reminders.useDefault` is true, use the calendar's default Reminders; otherwise use `reminders.overrides`, keeping only `method == popup`.
- RN-05: Overlapping Triggers are queued — one animation plays at a time (FIFO).

## MVP scope
- **In:** Google OAuth connect (read-only, including the account's email for display) with Keychain-stored token; reading timed Events from the primary calendar; resolving popup Reminders; airplane + banner Overlay over all windows; menu bar control (status incl. connected email, on/off, test, reconnect, Flight Speed, Banner color, quit); queueing overlapping animations.
- **Out (for now):** publishing/notarization/distribution; actions on the Event (open Meet/Zoom link); rich settings UI beyond Flight Speed and Banner color presets (e.g. custom colors, banner size); multiple Google accounts; all-day Events; multi-monitor targeting beyond the main screen.

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
| Event | _A Google Calendar entry with a start time (timed); all-day entries are out of scope._ | "meeting", "appointment" |
| Reminder | _A `popup` notification configured on an Event, expressed as minutes before its start._ | "notification", "alert" |
| Trigger | _The computed moment to fire the animation: `Event start − Reminder minutes`._ | "alarm", "job" |
| Overlay | _The transparent, always-on-top window that draws the animation; click-through except while flying, when a click skips it (RF-09)._ | "popup", "window" |
| Airplane | _The little plane that flies across the Overlay pulling the banner._ | "plane sprite" |
| Banner | _The strip pulled by the Airplane, showing the Event text._ | "faixa", "ribbon", "label" |
| Poll | _The periodic fetch of upcoming Events from the Google Calendar API._ | "sync", "refresh" |
| Flight Speed | _The animation-speed preset (Slow/Normal/Fast) controlling how fast the Airplane crosses the Overlay; user-selectable from the menu bar and persisted across restarts._ | "animation speed", "duration" |
