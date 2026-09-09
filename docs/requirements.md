---
id: REQ-01
type: requirements
title: Requirements and glossary
status: approved
updated: 2026-09-09
parents: []
children: [AYD-001, AYD-004, AYD-006, AYD-007, AYD-008, AYD-009, AYD-010]
related: [GLO]
---

# Requirements

> macOS app that connects to Google Calendar and flies an airplane pulling a banner across
> the screen at each event's reminder time. It is **source-available and sold on trust**
> (RNF-12): anyone can clone the repository, plug in their own Google OAuth client and run it
> for free; what is sold is the convenience of the **Distributed Build** — signed, notarized,
> credentials included, auto-updating (RF-16), downloaded as a `.dmg` or installed with
> Homebrew (RNF-07). It is **not** an App Store app (AYD-009 supersedes AYD-003). Keep it
> lean, but hold it to a distributable bar on security and privacy (RNF-05, RNF-08, RNF-10,
> RNF-11).

## Functional (RF)
| ID | Requirement | Priority | Acceptance criterion |
|----|-------------|----------|----------------------|
| RF-01 | Connect to Google Calendar (read-only) via OAuth | Must | The user authorizes each Google Account once in the browser; every connected Account stays connected across restarts without re-authorizing |
| RF-02 | Read timed Events from each selected Calendar | Must | Events with a start time are read from every selected Calendar (RF-10); all-day Events are ignored (RN-01) |
| RF-03 | Resolve each Event's effective popup Reminders | Must | For each Event, the app derives its Reminders from `overrides` or the calendar defaults, keeping only `popup` (RN-04) |
| RF-04 | Fly the airplane + banner Overlay at each Reminder time | Must | At `Event start − Reminder minutes`, an airplane pulling a banner slides across the screen over all windows (RN-02) |
| RF-05 | The banner shows the Event and time | Must | The banner text reads on two centered lines — `<Title>` in bold, then `at HH:MM (in X min)` in italic; the Banner keeps a fixed width, widening on demand for a long title rather than hiding it |
| RF-06 | Menu bar control | Must | From the menu bar the user can see connection status (including every connected Account's email), toggle the app on/off, test the animation, manage Accounts — add, reconnect, or sign out each one (RF-14) — choose the Airplane's Flight Speed, choose the Banner's color (preset or the Event's Calendar Color, RF-13), choose which Calendars to be alerted on per Account (RF-10), check for updates (RF-16), and quit |
| RF-07 | Choose the Airplane's Flight Speed | Must | The menu bar offers 3 Flight Speed presets (Slow/Normal/Fast); the selection persists across restarts, applies from the next animation on, and the Airplane crosses any screen size at the same visual speed |
| RF-08 | Choose the Banner's color | Must | The menu bar offers a set of Banner color presets; the selection persists across restarts and applies from the next animation on |
| RF-09 | Skip a playing Reminder animation | Should | While the airplane + banner Overlay is flying, a click anywhere on the screen accelerates it to cover the remaining distance in ~1.5s instead of blocking the click through |
| RF-10 | Choose which Calendars to be alerted on | Should | The menu bar lists every Calendar of each connected Account, grouped under that Account, with a multi-select control; only selected Calendars generate Triggers; the selection persists **per Account** across restarts and applies from the next Poll on. Default when the user has not chosen, for a given Account: all of that Account's Calendars |
| RF-12 | Manually force a Poll from the menu bar | Should | The menu bar offers a "Refresh now" control, always clickable regardless of whether a Trigger is currently upcoming, so a stale sync can be corrected without waiting for the next background Poll; while the triggered Poll is in flight the control reads "Refreshing…" and is disabled. Unlike the background Poll (RNF-06), the manual one is a **full resync**: it refetches the whole window and rebuilds the upcoming Triggers from it, so Triggers whose Event was deleted or rescheduled are dropped |
| RF-13 | Paint the Banner with the Event's Calendar Color | Should | The menu bar offers a "Match calendar color" toggle inside the Banner color control; while it is on, each Banner is painted with the Calendar Color of the Calendar the Event came from, and the Banner text keeps a readable contrast against it; while it is off, every Banner uses the chosen color preset (RF-08). The preset is also the fallback when the Calendar has no color and for the test animation. The toggle persists across restarts and applies from the next animation on |
| RF-14 | Connect more than one Google Account | Should | From the menu bar's "Accounts" submenu the user can connect additional Google Accounts (each authorized separately, RF-01), see each Account's connection status and email, choose that Account's Calendars (RF-10), reconnect it, or sign it out — independently of the other connected Accounts. Every connected Account's selected Calendars generate Triggers; one Account's connection failure doesn't affect the others (RNF-04) |
| RF-15 | Choose which Reminders fire | Should | The menu bar offers a "Reminders" submenu where the user switches the Event's own Reminders on/off and checks any number of **Extra Reminders** from a fixed set (at start, 1, 5, 10, 15 minutes before); every Event's effective Reminders are the union of both (RN-07). The selection is app-wide, persists across restarts, and rebuilds the upcoming Triggers as soon as it changes — no waiting for the next Poll. The submenu also states the current selection, and warns when nothing is selected (no Event would ever be announced) |
| RF-16 | Check for and install updates | Must | The app checks the Appcast for a newer Release on a schedule and on demand from the menu bar ("Check for updates…"), states the version it is running, shows what changed, and installs with the user's consent and a relaunch; an update whose signature does not verify is refused (RNF-11). The automatic check is opt-in on first launch and toggleable afterwards. Applies to the **Distributed Build** only — a **Source Build** never self-updates |

## Non-functional (RNF)
| ID | Category | Requirement | Target |
|----|----------|-------------|--------|
| RNF-01 | Footprint | Runs as a background menu bar agent | `LSUIElement` app, no Dock icon |
| RNF-02 | Overlay behavior | The Overlay never steals focus, and appears above everything; it is click-through except while a Reminder animation is playing, when a click skips it (RF-09) | Shows over fullscreen apps and all Spaces; clicks pass through to the window below when idle; never activates the app or takes key focus, even mid-flight |
| RNF-03 | Precision | The Trigger fires close to the computed time | Error < 5 s from the computed fire time |
| RNF-04 | Resilience | Tolerant to sleep/wake and network loss | Re-syncs on wake; keeps scheduled Triggers across transient network failures |
| RNF-05 | Security | The **user's** secrets are stored securely | Each connected Account's OAuth access/refresh tokens live only in the macOS Keychain, keyed separately per Account, never in plaintext on disk |
| RNF-06 | Network | Efficient calendar sync | Incremental poll using `syncToken` |
| RNF-07 | Distribution | Distributed **directly**, outside the Mac App Store | Signed with a Developer ID certificate, notarized and stapled, shipped as a `.dmg` from a public landing page and as a Homebrew Cask; Gatekeeper opens it on a clean machine with no warning and no right-click-to-open workaround. The Mac App Store is **explicitly out of scope** — with it go App Review, the demo-account requirement and the store's update mechanism (AYD-009, which supersedes AYD-003) |
| RNF-08 | Privacy compliance | Declares data collection and use to the user and to Google | Ships a public privacy-policy URL and a landing page on a domain the project controls; the `calendar.readonly` restricted scope passes Google verification. The `PrivacyInfo.xcprivacy` manifest is kept as good practice but is no longer a gate, being an App Store requirement (AYD-010, which supersedes AYD-005) |
| RNF-09 | Quality gate | Every change is built, tested, and linted automatically | CI builds the app, runs the test suite, and lints the sources on each push/PR; a failure blocks the merge (AYD-004) |
| RNF-10 | Security (app credential) | The **app's** OAuth client secret is not exposed | Two levels. **Now (must):** the secret is not in the repository at all — the source is public (RNF-12), so it is injected at build time and ships only in the Distributed Build (TDR-007). **Target:** the token exchange/refresh runs behind an app-owned backend (token broker) so the secret never ships in a binary either; auto-update (RF-16) makes rotating it a same-day operation instead of a reinstall (AYD-009) |
| RNF-11 | Security (update channel) | An update can only come from the project | Every Release is EdDSA-signed and its Appcast served over HTTPS; the app refuses any update whose signature does not verify against the public key embedded in the binary, so control of the feed or of the download host is not enough to ship code to a user's machine. The private signing key exists only in a Keychain and as a CI secret, never in the repository (AYD-009, TDR-006) |
| RNF-12 | Distribution model | Source-available, sold on trust | The repository builds and runs a **fully functional** app with no purchase, no license key, no feature gate, no trial timer and no phone-home; the builder supplies their own Google OAuth client (TDR-007). What a purchase buys is the Distributed Build's convenience — signed, notarized, credentials included, auto-updating — never a capability withheld from the source (AYD-009). The repository is licensed under PolyForm Shield 1.0.0 (`LICENSE.md`): free to clone, build and use for any purpose, but not to redistribute as a competing product |

## Business rules
- RN-01: Only timed Events generate Triggers; all-day Events are ignored.
- RN-02: A Trigger fires at `Event start − Reminder minutes`, one per popup Reminder of the Event.
- RN-03: The same Reminder never fires twice (dedupe by `accountId#calendarId#eventId#minutes`, RF-14).
- RN-04: If `reminders.useDefault` is true, use the calendar's default Reminders; otherwise use `reminders.overrides`, keeping only `method == popup`.
- RN-05: Overlapping Triggers are queued — one animation plays at a time (FIFO).
- RN-06: If an Event's resolved popup Reminders (RN-04) are empty, add a single 5-minutes-before
  Reminder; otherwise use the resolved set unchanged. Applies only while the Event's own
  Reminders are in use (RN-07); it is the fallback of that branch, not of the union.
- RN-07: An Event's **effective** Reminders are the union, deduped by minutes, of (a) its own
  Reminders resolved per RN-04/RN-06, while "Event's own reminders" is on, and (b) every Extra
  Reminder the user checked (RF-15). Both branches are independent: an Extra Reminder never
  suppresses RN-06's fallback, and an Event whose own Reminder already matches an Extra
  Reminder still fires once for that minute (RN-03). When the union is empty, the Event
  generates no Trigger.

## MVP scope
- **In:** Google OAuth connect (read-only, including each connected Account's email for display) with Keychain-stored tokens; connecting **more than one Google Account at the same time** (RF-14); reading timed Events from the selected Calendars of every connected Account; choosing which Calendars to be alerted on, per Account (RF-10); resolving popup Reminders; choosing which Reminders fire — the Event's own plus any Extra Reminders (RF-15); airplane + banner Overlay over all windows; menu bar control (status incl. connected emails, on/off, test, Accounts submenu — add/reconnect/sign out per Account, RF-14 — Flight Speed, Banner color, Calendar selection, Reminders, quit); queueing overlapping animations.
- **Out (for now):** actions on the Event (open Meet/Zoom link); rich settings UI beyond Flight Speed, Banner color, and Calendar selection presets (e.g. custom colors, banner size); non-Google calendar sources (e.g. iCloud); all-day Events; multi-monitor targeting beyond the main screen.
- **Out for good:** the Mac App Store, and with it App Sandbox as a *distribution* obligation, App Review, and store-managed updates (RNF-07, AYD-009).

## Post-MVP: shipping it (planned)
The app is **source-available and sold on trust** (RNF-12), distributed **directly** rather than
through the Mac App Store (RNF-07). Two user paths, one codebase:

- **Source Build** — clone, register your own Google OAuth client, build, run. Free, unrestricted,
  never self-updates.
- **Distributed Build** — the `.dmg` (or Homebrew Cask) the project signs, notarizes and ships with
  its own credentials; it self-updates (RF-16). This is what a purchase buys, and the only
  difference between the two.

The remaining work sits in independent AYDs, each with a defined boundary: **AYD-009** (direct
distribution, release pipeline & auto-update — RF-16, RNF-07, RNF-11, RNF-12), **AYD-010** (signing,
sandbox and the compliance artifacts that survive outside the store — RNF-08), and **AYD-004** (CI &
code-quality gate — RNF-09, already shipped). AYD-009 depends on the signing configuration AYD-010
defines.

The **revoked direction.** RNF-07 previously targeted the Mac App Store (AYD-003, AYD-005). It is
withdrawn, not deferred: the store forbids an app from updating itself, which is incompatible with
RF-16, and it adds App Review latency and a revenue share to a product that needs neither. The old
AYDs stay frozen as the historical design; AYD-009 and AYD-010 supersede them.

Two credential problems remain open and are **not** solved by dropping the store. The client secret
is currently committed in the repository, which a public source tree turns into a disclosure — it is
rotated and moved to build-time injection by TDR-007 (RNF-10, must). Removing it from the binary too
still requires the token broker, which stays the target; auto-update makes that migration shippable
without asking anyone to reinstall.

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
| Account | _A connected Google Account: an OAuth session, identified by Google's own immutable account id, that owns a set of Calendars. The app can hold several Accounts connected at the same time (RF-14), each with its own connection status and Calendar selection (RF-10)._ | "user", "session", "profile" |
| Calendar | _A Google Calendar belonging to a connected Account (its `primary` one or a secondary/subscribed one). The user selects which Calendars generate Triggers, per Account (RF-10)._ | "agenda", "list" |
| Event | _A Google Calendar entry with a start time (timed); all-day entries are out of scope._ | "meeting", "appointment" |
| Reminder | _A `popup` notification configured on an Event, expressed as minutes before its start._ | "notification", "alert" |
| Trigger | _The computed moment to fire the animation: `Event start − Reminder minutes`._ | "alarm", "job" |
| Overlay | _The transparent, always-on-top window that draws the animation; click-through except while flying, when a click skips it (RF-09)._ | "popup", "window" |
| Airplane | _The little plane that flies across the Overlay pulling the banner._ | "plane sprite" |
| Banner | _The strip pulled by the Airplane, showing the Event text._ | "faixa", "ribbon", "label" |
| Poll | _The periodic fetch of upcoming Events from the Google Calendar API._ | "sync", "refresh" |
| Calendar Color | _The color a Calendar is painted with in Google Calendar, returned by the API as a hex value; optionally used as the Banner's color (RF-13)._ | "calendar theme", "event color" |
| Extra Reminder | _A Reminder the app itself adds to every Event, chosen from a fixed set of minutes-before presets in the menu bar (RF-15), on top of — or instead of — the Event's own Reminders._ | "custom reminder", "default alert" |
| Flight Speed | _The animation-speed preset (Slow/Normal/Fast) controlling how fast the Airplane crosses the Overlay; user-selectable from the menu bar and persisted across restarts._ | "animation speed", "duration" |
| Release | _A published, versioned build of the app: a signed and notarized `.dmg` plus the entry that announces it in the Appcast._ | "build", "version bump" |
| Appcast | _The signed feed of Releases the app reads to learn whether a newer one exists (RF-16)._ | "update feed", "manifest" |
| Distributed Build | _The Release the project itself builds, signs, notarizes and ships with its own Google OAuth credentials — the plug-and-play artifact a purchase buys (RNF-12), and the only build that self-updates._ | "official build", "paid version" |
| Source Build | _An app built from the repository by anyone, with their own Google OAuth credentials (RNF-12). Fully functional and identical in features; unsigned by the project, so it never self-updates._ | "dev build", "free version", "community build" |
