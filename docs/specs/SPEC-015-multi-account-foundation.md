---
id: SPEC-015
type: spec
status: draft
parents: [AYD-007]
related: [GLO, AYD-002, SPEC-005]
updated: 2026-09-03
---

# SPEC-015: Multi-account foundation — what + how

> Replaces the single app-wide `AuthManager`/`CalendarService` pair with one
> `AccountSession` per connected Google Account, orchestrated by a new `AccountRegistry`,
> and migrates the one Account already connected today without a re-auth prompt. The
> menu bar keeps rendering today's flat "Calendars" submenu against the single migrated
> Account — SPEC-016 is what turns it into the per-Account "Accounts" submenu.
> Implements AYD-007; doesn't redefine it.

## What (goal)
The app can hold several Google Accounts connected at once: each is independently
authorized, has its own Keychain-stored token and Calendar selection, is polled and can
fail/be revoked independently, and contributes its Triggers (deduped per-Account) to the
same Scheduler/Overlay. An existing single-account install upgrades to this silently.

## Acceptance criteria
```gherkin
Scenario: Two Accounts both contribute Triggers
  Given Account A has Calendar Ca with a Reminder-bearing Event
  And Account B has Calendar Cb with a Reminder-bearing Event
  When a Poll runs
  Then Triggers from both A and B are returned
  And their ids are prefixed "A#..." and "B#..." respectively

Scenario: Same Calendar id shared by two Accounts does not collide
  Given Account A and Account B both expose a Calendar with id "shared@group.calendar.google.com"
  And each holds an Event with the same event id and the same popup minutes
  When a Poll runs
  Then two distinct Triggers are produced, one per Account

Scenario: One Account's revoked session doesn't affect the other
  Given Account A is connected and Account B's refresh token is revoked
  When a Poll runs
  Then Account B's session becomes needsReauth
  And Account A's Triggers are still returned

Scenario: One Account's network failure doesn't affect the other
  Given Account A is connected and Account B is unreachable
  When a Poll runs
  Then Account B's connection status is left unchanged
  And Account A's Triggers are still returned

Scenario: A total outage during a full resync doesn't wipe the armed Triggers
  Given Account A is connected with an armed Trigger
  And every connected Account fails this Poll round
  When refreshNow() (a full resync) runs
  Then anyAccountSucceeded is false
  And the Scheduler's armed set is left untouched

Scenario: Adding a second Account registers it without disturbing the first
  Given Account A is already connected with a stored token and Calendar selection
  When addAccount(.google) resolves to a new Account B
  Then both A and B appear in the registry's sessions
  And A's stored token and Calendar selection are untouched

Scenario: Adding an already-connected Account updates it instead of duplicating it
  Given Account A is already connected
  When addAccount(.google) resolves to Account A again (same id)
  Then the registry still holds exactly one session for A
  And A's stored token is refreshed with the new one

Scenario: Reconnecting one Account resolving to a different identity registers that identity
  Given Account A is connected
  When reconnect(A.id) completes and identity() resolves to Account C (different id)
  Then Account C is registered
  And Account A's stored token is untouched

Scenario: Signing out one Account leaves the others connected
  Given Accounts A and B are both connected
  When signOut(A.id) is called
  Then A's Keychain entry and Calendar selection are deleted
  And B's session and stored data are untouched

Scenario: Legacy single-account token migrates silently
  Given no Accounts are registered
  And a refresh token exists under the legacy unscoped Keychain key
  And a Calendar selection exists under the legacy unscoped UserDefaults key
  When restore() runs and identity() resolves successfully
  Then exactly one Account is registered
  And its token is stored under the Account-scoped Keychain key
  And its Calendar selection is copied to the Account-scoped key
  And both legacy keys are deleted

Scenario: Legacy migration clears a dead legacy token without registering an Account
  Given no Accounts are registered
  And the legacy refresh token is rejected by Google (refreshTokenRevoked)
  When restore() runs
  Then no Account is registered
  And the legacy Keychain key is deleted

Scenario: Legacy migration is deferred on a network failure
  Given no Accounts are registered
  And the legacy refresh token exists but identity() fails with a network error
  When restore() runs
  Then no Account is registered
  And the legacy Keychain key is left untouched
```

## How (approach)
`Account {id, provider, label}` is the new domain identity, with `id` namespaced
`"google:<sub>"`. `KeychainStore` takes its `account` key as an init parameter instead of
a fixed constant, so each `AccountSession` gets its own Keychain entry
(`google-refresh-token#<accountId>`); `CalendarSelectionStore`'s concrete
`UserDefaultsCalendarSelectionStore` does the same for `selectedCalendarIds.<accountId>`.
A new `AccountStore` persists the ordered list of connected `Account`s as JSON.
`AuthManager` gains `identity()` (decodes `sub`+`email` from the existing `userinfo` call)
and `connect(loginHint:)` (adds `prompt=select_account consent` and an optional
`login_hint` to the authorization URL); both are the two methods, plus `disconnect()` and
`isConnected`, that make up the new narrow `AccountAuthenticating` protocol —
`AuthManaging` now refines it. A new `AccountRegistry` (implementing `AccountsManaging`)
owns one `AccountSession` (auth + calendar service pair, both built through an injected
factory) per registered `Account`; it fans `poll(fullResync:)` out across sessions
in sequence, isolating each session's error into its own `connectionStatus`, and returns
`(triggers: [Trigger], anyAccountSucceeded: Bool)` — the second element is what lets
`AppCoordinator` skip `scheduler.cancelAll()` on a full resync when *every* Account failed
this round (a total outage), instead of wiping every armed Trigger over what an empty
`[Trigger]` alone couldn't distinguish from "nothing upcoming" (RNF-04). It also
implements `addAccount`/`reconnect`/`signOut` using a provisional in-memory-token
`AuthManager` to resolve identity before committing to the Keychain. `restore()` calls a
`LegacyAccountMigration` helper first, which only acts when `AccountStore.accounts` is
empty. `CalendarService` takes an `accountId` and prefixes it onto every `Trigger.id`.
`AppState` moves from one flat `connectionStatus`/`calendars` pair to `[AccountState]`
plus a computed `statusTitle`. `AppCoordinator` is rewired onto `AccountsManaging`;
`logout()`/`reconnect()` become per-Account, and `addAccount()` is new. The menu bar is
untouched in this SPEC beyond what's needed to keep building against the single migrated
Account — `StatusMenuController` keeps rendering `state.accounts.first`'s Calendars under
today's flat "Calendars" item; SPEC-016 replaces that with the real "Accounts" submenu.

## Steps
1. **`Models/Account.swift`** *(new)* — `enum AccountProvider: String, Codable { case google }`;
   `struct Account: Identifiable, Equatable, Codable { let id: String; let provider:
   AccountProvider; let label: String }` with `static func id(provider:, providerUserId:)
   -> String` building `"\(provider.rawValue):\(providerUserId)"`.
2. **`Auth/KeychainStore.swift`** — `init(service:, account: String = "google-refresh-token")`;
   add `static func accountScopedKey(_ accountId: String) -> String` returning
   `"google-refresh-token#\(accountId)"`. Existing single-account callers keep working via
   the default.
3. **`Accounts/AccountStore.swift`** *(new)* — `protocol AccountStoring: AnyObject { var
   accounts: [Account] { get set } }` + `UserDefaultsAccountStore` (JSON-encoded array
   under key `connectedAccounts`; empty array when the key is absent, mirroring
   `CalendarSelectionStore`'s boundary pattern).
4. **`Calendar/CalendarSelectionStore.swift`** — `UserDefaultsCalendarSelectionStore.init`
   takes `accountId: String` and derives its key as `"selectedCalendarIds.\(accountId)"`;
   the protocol and its `isSelected`/`setSelected` extension are unchanged.
5. **`Auth/AuthManager.swift`**:
   - Add `protocol AccountAuthenticating { var isConnected: Bool { get }; func
     connect(loginHint: String?) async throws; func identity() async throws -> Account;
     func disconnect() async }`; make `AuthManaging` refine it and drop its own
     `userEmail()` (replaced by `identity()`).
   - `identity()` decodes `{sub, email}` from the same `oauth2/v3/userinfo` call
     `userEmail()` used, returning `Account(id: Account.id(provider: .google,
     providerUserId: sub), provider: .google, label: email)`.
   - `connect(loginHint:)` replaces `connect()`; the authorization URL gains
     `prompt=select_account consent` (was `consent`) and, when `loginHint` is non-nil,
     `login_hint=<value>`. Add `extension AuthManaging { func connect() async throws {
     try await connect(loginHint: nil) } }` so existing single-arg callers don't need to
     change everywhere at once.
6. **`Accounts/AccountRegistry.swift`** *(new)*:
   - `struct AccountSession { let account: Account; var connectionStatus:
     ConnectionStatus; var calendars: [CalendarInfo] }` plus the internal (not part of the
     protocol) pair of live services the registry holds per session.
   - `protocol AccountsManaging: AnyObject { var sessions: [AccountSession] { get };
     func restore() async; func verifySessions() async; func addAccount(provider:
     AccountProvider) async throws -> Account; func reconnect(accountId: String) async
     throws; func signOut(accountId: String) async; func poll(fullResync: Bool) async ->
     (triggers: [Trigger], anyAccountSucceeded: Bool) }`.
   - `final class AccountRegistry: AccountsManaging` (a `@MainActor` class, mirroring
     `AppCoordinator`) constructed with an `AccountStoring`, a `LegacyAccountMigrating`, a
     `scopedTokenStore: (String) -> TokenStoring` and `scopedCalendarSelectionStore:
     (String) -> CalendarSelectionStoring` (both testable without touching the real
     Keychain/UserDefaults), a `provisionalAuthFactory: (TokenStoring) ->
     AccountAuthenticating`, and a `sessionFactory: (Account, TokenStoring,
     CalendarSelectionStoring) -> (auth: AccountAuthenticating, calendar:
     CalendarServicing)` — the real factories (wired in `AppDelegate`) build real
     `KeychainStore`/`UserDefaultsCalendarSelectionStore`/`AuthManager`/`GoogleCalendarAPI`/
     `CalendarService`(accountId:) instances; tests inject fakes for all of them.
   - `addAccount(provider:)`: build a provisional `AuthManager` over an in-memory
     `TokenStoring`, call `connect(loginHint: nil)`, then `identity()`. If the resolved
     `Account.id` matches an existing session, replace that session's stored token and
     rebuild its `AccountSession` (update path); otherwise persist the token under
     `KeychainStore.accountScopedKey(id)`, append the `Account` to `AccountStore`, and
     build a new `AccountSession`.
   - `reconnect(accountId:)`: same provisional-auth flow, but with `loginHint` set to the
     existing session's `label`; whatever `Account` `identity()` resolves to (usually the
     same id, but not guaranteed) is registered/updated per the same rule as `addAccount`
     — critically, a token is only ever written under the id `identity()` actually
     returned, never blindly under `accountId`.
   - `signOut(accountId:)`: delete that Account's Keychain entry (`KeychainStore(account:
     accountScopedKey(id)).setRefreshToken(nil)`), remove it from `AccountStore` and
     `sessions`, and clear `selectedCalendarIds.<accountId>` from `UserDefaults`.
   - `poll(fullResync:)`: for each session, call its `CalendarServicing.poll(fullResync:)`;
     on success, merge the Triggers, record that this session succeeded (folded into the
     returned `anyAccountSucceeded`), and set `connectionStatus = .connected`; on
     `AuthError.refreshTokenRevoked`, set that session's `connectionStatus = .needsReauth`
     and continue with the rest; on any other error, log and leave `connectionStatus` as-is
     (RNF-04) and continue. Also refresh that session's `calendars` via
     `availableCalendars()`.
   - `verifySessions()`: for each session, call `identity()` (or a lighter authenticated
     probe) to move `.connecting` → `.connected`/`.needsReauth`, mirroring today's
     `AppCoordinator.verifySession()`.
7. **`Accounts/LegacyAccountMigration.swift`** *(new)* — a small stateless helper called
   from `AccountRegistry.restore()` when `accountStore.accounts.isEmpty`: reads the legacy
   `KeychainStore()` (default `account: "google-refresh-token"`), and if a token is
   present, builds a provisional `AuthManager` over it and calls `identity()`. On success:
   write the token under the scoped key, copy the legacy
   `UserDefaultsCalendarSelectionStore` value to the scoped key, register the `Account`,
   delete both legacy keys. On `AuthError.refreshTokenRevoked`: delete the legacy Keychain
   key only. On any other error: do nothing (retry next `restore()`).
8. **`Calendar/CalendarService.swift`** — add a required `accountId: String` to `init`;
   build `Trigger.id` as `"\(accountId)#\(calendarId)#\(event.id)#\(minutes)"`.
9. **`App/AppState.swift`**:
   - `struct AccountState: Identifiable, Equatable { let id: String; let label: String;
     var connectionStatus: ConnectionStatus; var calendars: [CalendarInfo] = [] }`.
   - `AppState.connectionStatus`/`calendars` replaced by `var accounts: [AccountState] =
     []`.
   - `ConnectionStatus` loses its `.connected(email:)` payload (email now lives on
     `AccountState`) — becomes a plain `case connected` alongside
     `disconnected`/`connecting`/`needsReauth`.
   - Add `var statusTitle: String { get }`: `"Not connected"` (no accounts or all
     disconnected), `"Connecting…"` (any connecting, none connected yet),
     `"Connected as \(label)"` (exactly one account, connected),
     `"Connected · N accounts"` (N ≥ 2, all connected),
     `"N accounts · M need reconnecting"` (any `.needsReauth` present).
10. **`App/AppCoordinator.swift`** — replace the `auth`/`calendar` properties with a
    single `accounts: AccountsManaging`. `start()`: `await accounts.restore()` → notify →
    `await accounts.verifySessions()` → notify → `await poll()`. `poll(fullResync:)`: `let
    result = await accounts.poll(fullResync:)`; `scheduler.cancelAll()` only runs when
    `fullResync && result.anyAccountSucceeded` (a total outage across every Account must
    not wipe the armed set, RNF-04); then `scheduler.schedule(result.triggers)`, and
    rebuild `state.accounts` from `accounts.sessions` and `state.nextTrigger` from the
    Scheduler as today. `logout()`/`reconnect()` take an `accountId: String` — renamed
    `signOut(accountId:)`/`reconnect(accountId:)` — and call
    `accounts.signOut(accountId:)`/`accounts.reconnect(accountId:)`; add `addAccount()`
    calling `accounts.addAccount(provider: .google)` then re-Polling (mirrors
    `calendarsChanged()`).
11. **`App/AppDelegate.swift`** — build the real `AccountRegistry` with a session factory
    that constructs `AuthManager(config: .embedded, tokenStore: KeychainStore(account:
    KeychainStore.accountScopedKey(account.id)), ...)` and
    `CalendarService(api:, accountId: account.id, selectionStore:
    UserDefaultsCalendarSelectionStore(accountId: account.id))`; pass it to
    `AppCoordinator` in place of the current `authManager`/`calendarService`.

## Affected files
- `cal-reminder/Models/Account.swift` *(new)*
- `cal-reminder/Auth/KeychainStore.swift`
- `cal-reminder/Accounts/AccountStore.swift` *(new)*
- `cal-reminder/Calendar/CalendarSelectionStore.swift`
- `cal-reminder/Auth/AuthManager.swift`
- `cal-reminder/Accounts/AccountRegistry.swift` *(new)*
- `cal-reminder/Accounts/LegacyAccountMigration.swift` *(new)*
- `cal-reminder/Calendar/CalendarService.swift`
- `cal-reminder/App/AppState.swift`
- `cal-reminder/App/AppCoordinator.swift`
- `cal-reminder/App/AppDelegate.swift`
- `cal-reminderTests/AccountStoreTests.swift` *(new)*
- `cal-reminderTests/AccountRegistryTests.swift` *(new)*
- `cal-reminderTests/KeychainStoreTests.swift`
- `cal-reminderTests/CalendarSelectionStoreTests.swift`
- `cal-reminderTests/AuthManagerTests.swift`
- `cal-reminderTests/AppStateTests.swift` *(new)*
- `cal-reminderTests/AppCoordinatorTests.swift`
- `cal-reminderTests/CalendarServiceTests.swift`

## Tests
- **Acceptance:** the eleven Gherkin scenarios above map to `AccountRegistryTests`
  (two-Accounts poll, shared-Calendar-id no-collision, revoked/network isolation, add,
  add-already-registered, reconnect-resolves-different-identity, sign-out) and to a
  dedicated migration section of the same file (three migration scenarios) driven by fake
  `AccountStoring`/`TokenStoring`/`AccountAuthenticating`.
- **Unit:**
  - `AccountStoreTests`: round-trips `[Account]`, preserves insertion order, empty when
    unset.
  - `KeychainStoreTests`: two `KeychainStore`s with different `account` values don't see
    each other's token; the default `account` still reads the pre-existing legacy value.
  - `CalendarSelectionStoreTests`: two stores with different `accountId` are isolated;
    the legacy unscoped store (no `accountId` — kept as a distinct type/init path used
    only by the migration) still reads pre-existing data.
  - `AuthManagerTests`: `identity()` decodes `sub`+`email` into `Account`;
    `connect(loginHint:)`'s built authorization URL carries `prompt=select_account
    consent` and, when given, `login_hint`.
  - `AppStateTests`: `statusTitle` for 0/1/N accounts and with one `.needsReauth`.
  - `AppCoordinatorTests`: fakes rewritten against `AccountsManaging`; `poll()`
    populates `state.accounts` from multiple sessions; `logout(accountId:)`/
    `reconnect(accountId:)` target the right session; `addAccount()` re-Polls.
  - `CalendarServiceTests`: `Trigger.id` carries the injected `accountId` prefix.

## Checklist
- [ ] Two connected Accounts both contribute Triggers, prefixed correctly (`AccountRegistryTests`)
- [ ] A Calendar id shared by two Accounts produces two distinct Triggers (`AccountRegistryTests`)
- [ ] A revoked/unreachable Account doesn't affect the other's Triggers or status (`AccountRegistryTests`)
- [ ] A total outage across every Account during a full resync leaves the armed Triggers untouched (`AccountRegistryTests`, `AppCoordinatorTests`)
- [ ] Adding an Account already connected updates it instead of duplicating it (`AccountRegistryTests`)
- [ ] Reconnecting that resolves to a different identity registers that identity, not the old one (`AccountRegistryTests`)
- [ ] Signing out one Account leaves the others' stored data untouched (`AccountRegistryTests`)
- [ ] Legacy single-account token/selection migrate silently on first restore (`AccountRegistryTests`)
- [ ] A dead legacy token is cleared without registering an Account (`AccountRegistryTests`)
- [ ] A network failure during migration defers it to the next launch (`AccountRegistryTests`)
- [ ] `statusTitle` reads correctly for 0/1/N accounts and a needs-reconnect mix (`AppStateTests`)
- [ ] The existing single-account UI flow (menu, Poll, Reconnect, Sign out) still works end to end (manual)
