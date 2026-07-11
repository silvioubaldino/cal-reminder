---
id: ARCH
type: architecture
title: Architecture overview (living C4)
status: approved
updated: 2026-07-11
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
        auth["AuthManager"]
        cal["CalendarService"]
        sched["Scheduler"]
        overlay["OverlayPresenter"]
    end

    gcal[("Google Calendar API")]
    keychain[("macOS Keychain")]

    user -->|controls| ui
    user -->|sees| overlay
    ui --> coord
    coord --> auth
    coord --> cal
    auth -->|OAuth token| keychain
    cal -->|HTTPS · poll + syncToken| gcal
    cal -->|Triggers| sched
    sched -->|fire| overlay
    auth -.->|access token| cal
```

## Containers (legend)

| Container | Role | Stack |
|-----------|------|-------|
| **cal-reminder** | The whole app; a background menu bar agent that syncs Events and draws the airplane Overlay | Swift 5.9+ · AppKit (`NSStatusItem`, `NSPanel`) · Core Animation · `URLSession`/`Codable` · Keychain Services · Xcode (`LSUIElement` bundle) |
| **Google Calendar API** | Source of Events and Reminders (read-only) | Google Calendar REST v3 · OAuth 2.0 (Desktop/PKCE) |
| **macOS Keychain** | Secure storage of the OAuth refresh token | Keychain Services |

## Components (inside cal-reminder)

| Component | Responsibility | Detailed in |
|-----------|----------------|-------------|
| **MenuBar UI** | `NSStatusItem` menu: status, on/off, test, reconnect, Flight Speed, Banner color, Calendar selection, quit | AYD-001, AYD-002 |
| **AppCoordinator** | Wires modules together; holds `AppState`; re-Polls on Calendar-selection changes | AYD-001, AYD-002 |
| **AuthManager** | OAuth PKCE flow + token refresh + Keychain storage | AYD-001 |
| **CalendarService** | List Calendars, Poll each selected Calendar (per-Calendar sync), parse Events, resolve Reminders → Triggers | AYD-001, AYD-002 |
| **Scheduler** | Precise local timers per Trigger + dedupe + sleep/wake handling | AYD-001 |
| **OverlayPresenter** | `NSPanel` over all windows + animation + FIFO queue | AYD-001 |

> Diagram and table must stay in sync — if they diverge, **the table wins**.
