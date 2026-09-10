---
id: ARCH
type: architecture
title: Architecture overview (living C4)
status: approved
updated: 2026-09-10
parents: []
related: []
---

# Architecture overview (C4 — context + containers)

> **Living document.** Depicts the **current** topology: which modules exist and how
> they connect. Update it in the **same edit** that adds/removes a module or
> integration (see `conventions.md` §A.7). Names in **English** (they carry through to
> the code).

## Context (container view)

```mermaid
flowchart TB
    user["User (macOS)"]

    subgraph app["cal-reminder (macOS menu bar app)"]
        ui["MenuBar UI"]
        coord["AppCoordinator"]
        reg["AccountRegistry"]
        subgraph session["AccountSession (one per connected Account)"]
            auth["AuthManager"]
            cal["CalendarService"]
        end
        sched["Scheduler"]
        overlay["OverlayPresenter"]
        upd["UpdateController"]
    end

    gcal[("Google Calendar API")]
    keychain[("macOS Keychain")]
    rel[("Release host<br/>Appcast + .dmg")]

    user -->|controls| ui
    user -->|sees| overlay
    ui --> coord
    coord --> reg
    reg --> session
    auth -->|OAuth token, scoped per Account| keychain
    cal -->|HTTPS · poll + syncToken| gcal
    reg -->|merged Triggers| sched
    sched -->|fire| overlay
    auth -.->|access token| cal
    ui --> upd
    upd -->|HTTPS · signed Appcast| rel
```

## Containers (legend)

| Container | Role | Stack |
|-----------|------|-------|
| **cal-reminder** | The whole app; a background menu bar agent that syncs Events and draws the airplane Overlay | Swift 5.9+ · AppKit (`NSStatusItem`, `NSPanel`) · Core Animation · `URLSession`/`Codable` · Keychain Services · Xcode (`LSUIElement` bundle) |
| **Google Calendar API** | Source of Events and Reminders (read-only) | Google Calendar REST v3 · OAuth 2.0 (Desktop/PKCE) |
| **macOS Keychain** | Secure storage of the OAuth refresh token | Keychain Services |
| **Release host** | Serves the signed Appcast and the notarized `.dmg` the app updates itself from; also hosts the landing page and privacy policy | Static HTTPS hosting · GitHub Releases · Sparkle Appcast (EdDSA-signed) |

## Components (inside cal-reminder)

| Component | Responsibility | Detailed in |
|-----------|----------------|-------------|
| **MenuBar UI** | `NSStatusItem` menu: status, on/off, test, Reminders (Event's own + Extra Reminders), Accounts submenu (add/reconnect/sign out per Account, Calendar selection per Account), Flight Speed, Banner color, version + check for updates, quit | AYD-001, AYD-002, AYD-007, AYD-008, AYD-009 |
| **AppCoordinator** | Wires modules together; holds `AppState`; re-Polls on Calendar-selection changes, and full-resyncs on Reminder-selection changes | AYD-001, AYD-002, AYD-007, AYD-008 |
| **AccountRegistry** | Owns one `AccountSession` per connected Account; fans Poll out across them; handles add/reconnect/sign-out and the legacy single-account migration | AYD-007 |
| **AuthManager** *(one per connected Account)* | OAuth PKCE flow + token refresh + Keychain storage, scoped to its Account | AYD-001, AYD-007 |
| **CalendarService** *(one per connected Account)* | List that Account's Calendars, Poll each selected one (per-Calendar sync), keep a local replica of each Calendar's Events and derive the complete Trigger set from it every Poll, parse Events, resolve the effective Reminders (Event's own + Extra Reminders) → Triggers | AYD-001, AYD-002, AYD-007, AYD-008, AYD-011 |
| **Scheduler** | Precise local timers per Trigger + dedupe; reconciles the armed set against each Poll's complete result, scoped per Account; re-arms on wake instead of dropping | AYD-001, AYD-011 |
| **OverlayPresenter** | `NSPanel` over all windows + animation + FIFO queue | AYD-001 |
| **UpdateController** | Checks the Appcast for a newer Release, verifies its signature against the embedded public key, installs with the user's consent; inert in a Source Build | AYD-009, TDR-006 |

> Diagram and table must stay in sync — if they diverge, **the table wins**.
