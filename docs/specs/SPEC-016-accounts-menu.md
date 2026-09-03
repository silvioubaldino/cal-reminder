---
id: SPEC-016
type: spec
status: done
parents: [AYD-007]
related: [GLO, SPEC-015, SPEC-005]
updated: 2026-09-03
---

# SPEC-016: Accounts menu — what + how

> Replaces the flat "Calendars" menu item and the single top-level "Reconnect Google" /
> "Sign out of Google" pair with an "Accounts" submenu: one submenu per connected
> Account, holding that Account's Calendars, Reconnect, and Sign out, plus a trailing
> "Add Google account…". Built on top of SPEC-015's `AccountsManaging`/`AppState.accounts`.
> Implements AYD-007; doesn't redefine it.

## What (goal)
From the menu bar, the user can see every connected Account (email, connection status),
pick which Calendars alert them **per Account**, reconnect or sign out **one Account**
without touching the others, and connect an additional Google Account — closing RF-14
(and the RF-06/RF-10 menu changes it implies).

## Acceptance criteria
```gherkin
Scenario: No Accounts connected
  Given no Account is connected
  When the menu is opened
  Then the status line reads "Not connected"
  And the "Accounts" submenu shows only "Add Google account…"

Scenario: One connected Account renders like today
  Given exactly one Account "a@x.com" is connected
  When the menu is opened
  Then the status line reads "Connected as a@x.com"
  And the "Accounts" submenu has one entry "a@x.com" containing its Calendars,
    Reconnect, and Sign out

Scenario: Two connected Accounts each get their own submenu
  Given Accounts "a@x.com" and "b@y.com" are both connected
  When the menu is opened
  Then the status line reads "Connected · 2 accounts"
  And the "Accounts" submenu has two entries, each opening into that Account's own
    Calendars, Reconnect, and Sign out

Scenario: Toggling a Calendar only re-Polls and affects that Account
  Given Accounts "a@x.com" and "b@y.com" are both connected
  When the user unchecks a Calendar under "a@x.com"
  Then only "a@x.com"'s stored Calendar selection changes
  And a re-Poll is triggered

Scenario: Reconnect targets only that Account
  Given Accounts "a@x.com" and "b@y.com" are both connected
  When the user clicks "Reconnect" under "a@x.com"
  Then only "a@x.com"'s session is reconnected
  And the reconnect flow's login_hint is "a@x.com"

Scenario: Sign out removes only that Account from the menu
  Given Accounts "a@x.com" and "b@y.com" are both connected
  When the user clicks "Sign out" under "a@x.com"
  Then the "Accounts" submenu no longer lists "a@x.com"
  And "b@y.com" and its Calendars are still listed

Scenario: An Account needing reconnect is marked in the menu
  Given Account "a@x.com" is in the needsReauth state
  When the menu is opened
  Then "a@x.com"'s entry title is marked as needing reconnect

Scenario: Add Google account triggers the connect flow
  Given the "Accounts" submenu is open
  When the user clicks "Add Google account…"
  Then addAccount() is called
```

## How (approach)
A new `AccountsMenuBuilder` builds the "Accounts" `NSMenuItem`'s submenu from
`[AccountState]`: one row per Account (its own submenu, containing the same
`CalendarCheckboxView`-based Calendar checkboxes `StatusMenuController` already builds
for the single-account "Calendars" submenu, plus a separator, "Reconnect", and "Sign
out"), followed by a separator and "Add Google account…". `StatusMenuController` drops
its top-level `Calendars`/`Reconnect Google`/`Sign out of Google` items, replaces them
with the single "Accounts" item, and drives its status label from
`AppState.statusTitle` (SPEC-015) instead of switching on `connectionStatus` itself.
Because the set of Accounts (and thus the set of Calendar-selection stores) changes at
runtime, `StatusMenuController` takes a `calendarSelectionStore(accountId:) ->
CalendarSelectionStoring` factory instead of a single fixed store, and per-Account
callbacks `onReconnect(accountId:)` / `onSignOut(accountId:)`, plus the existing
`onCalendarsChanged` (still global — any Account's toggle re-Polls everything, same as
today) and a new `onAddAccount`.

## Steps
1. **`MenuBar/AccountsMenuBuilder.swift`** *(new)* — extracts the per-Calendar checkbox
   submenu construction (today's `rebuildCalendarsSubmenu` body) into a reusable
   `func calendarsSubmenu(for account: AccountState, selectionStore:
   CalendarSelectionStoring, onCalendarsChanged: @escaping () -> Void) -> NSMenu`, reusing
   the existing `CalendarCheckboxView`. Adds `func accountsMenu(for accounts:
   [AccountState], selectionStore: (String) -> CalendarSelectionStoring, onCalendarsChanged:
   @escaping () -> Void, onReconnect: @escaping (String) -> Void, onSignOut: @escaping
   (String) -> Void, onAddAccount: @escaping () -> Void) -> NSMenu`: for each `AccountState`,
   a submenu titled with the Account's `label` (prefixed `⚠︎ ` when
   `connectionStatus == .needsReauth`) containing `calendarsSubmenu(...)`, a separator,
   "Reconnect", and "Sign out"; below all Account rows, a separator and "Add Google
   account…". Empty `accounts` renders just "Add Google account…".
2. **`MenuBar/StatusMenuController.swift`**:
   - Remove `calendarsMenuItem`, `signOutItem`, the top-level "Reconnect Google" /
     "Sign out of Google" items, and `rebuildCalendarsSubmenu()`.
   - Add `accountsMenuItem`, built via `AccountsMenuBuilder` inside `render(_:)` from
     `state.accounts` (same pattern as today's `rebuildCalendarsSubmenu()` call).
   - `init` gains `calendarSelectionStore: @escaping (String) -> CalendarSelectionStoring`,
     `onReconnect: @escaping (String) -> Void`, `onSignOut: @escaping (String) -> Void`,
     `onAddAccount: @escaping () -> Void`; drops the single `calendarSelectionStore:
     CalendarSelectionStoring` parameter and the old parameterless `onReconnect`/`onSignOut`.
   - `render(_:)` sets `statusLabel.title = state.statusTitle` instead of switching on
     `connectionStatus` inline.
3. **`App/AppDelegate.swift`** — pass a `calendarSelectionStore` factory
   (`{ UserDefaultsCalendarSelectionStore(accountId: $0) }`), and wire
   `onReconnect`/`onSignOut` to `coordinator?.reconnect(accountId:)` /
   `coordinator?.signOut(accountId:)` (SPEC-015's per-Account signatures), and
   `onAddAccount` to `coordinator?.addAccount()`.

## Affected files
- `cal-reminder/MenuBar/AccountsMenuBuilder.swift` *(new)*
- `cal-reminder/MenuBar/StatusMenuController.swift`
- `cal-reminder/App/AppDelegate.swift`
- `cal-reminderTests/AccountsMenuBuilderTests.swift` *(new)*

## Tests
- **Acceptance:** the menu-rendering scenarios above (empty/one/two Accounts, per-Account
  Reconnect/Sign out isolation, needsReauth marker, Add Google account) are verified
  **manually** — `NSMenu` construction isn't practically unit-testable without a running
  `NSApplication`, same reasoning `SPEC-005`'s checklist already applied to its Calendars
  submenu.
- **Unit:** `AccountsMenuBuilder`'s pure `accountsMenu(for:...)`/`calendarsSubmenu(for:...)`
  functions turned out callable headless (constructing `NSMenu`/`NSMenuItem` doesn't need a
  running app) — `AccountsMenuBuilderTests` covers: row count for 0/2 Accounts; the trailing
  "Add Google account…" item; a `.needsReauth` Account's title carrying the warning marker;
  each Account row's submenu structure (Calendars / separator / Reconnect / Sign out); the
  Calendars submenu's empty-state placeholder and one row per Calendar. What it can't cover
  headlessly — actual click dispatch through `NSMenuItem.target`/`action`, and the resulting
  re-Poll/reconnect/sign-out wiring — stays manual, per the Checklist.

## Checklist
- [ ] Menu with 0 Accounts shows "Not connected" and only "Add Google account…" (manual)
- [ ] Menu with 1 Account matches today's single-account experience (manual)
- [ ] Menu with 2+ Accounts lists each with its own Calendars/Reconnect/Sign out (manual)
- [ ] Toggling a Calendar under one Account only changes that Account's selection (manual)
- [ ] Reconnect under one Account only reconnects that Account (manual)
- [ ] Sign out under one Account removes only that Account from the menu (manual)
- [ ] A needsReauth Account is visibly marked (manual)
- [ ] "Add Google account…" invokes the connect flow (manual)
