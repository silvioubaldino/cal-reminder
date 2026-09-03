---
id: TDR-005
type: tdr
title: Account identity, id namespacing, and per-Account Keychain/UserDefaults scoping
status: accepted
updated: 2026-09-03
parents: [SPEC-015]
related: [AYD-007, REQ-01]
superseded_by: null
---

# TDR-005: Account identity, id namespacing, and per-Account Keychain/UserDefaults scoping

> Append-only: never rewrite. A new decision = a new TDR that supersedes this one
> (`superseded_by`).

## Context
AYD-007 moves `AuthManager`/`CalendarService` from app-wide singletons to one instance per
connected `Account`. That requires deciding: (1) what identifies an Account, (2) how its stored
data — Keychain token, `selectedCalendarIds` — is keyed so two Accounts never collide or leak
into each other, and (3) what happens to the one Account already connected under the old,
unscoped storage on a user's existing install.

## Decision

**Identity: Google's `sub`, not the email.** The `oauth2/v3/userinfo` endpoint the app already
calls for `userEmail()` also returns `sub` — a stable, Google-assigned account id that survives
an email rename (Workspace domain change, alias switch). The email becomes a display-only
`label`; nothing keys storage by it. `Account.id` is namespaced as `"google:\(sub)"` rather than
the bare `sub`, and `Account` carries an explicit `provider: AccountProvider` field even though
`.google` is the only case today — both exist solely so that *if* a non-Google source is ever
added (AYD-007 "Open questions" — not implemented here), its ids can't collide with a Google
`sub` and no existing Account's stored data needs re-keying to make room for the distinction.

**Keychain scoping:** `KeychainStore` gains an `account` parameter (was the fixed constant
`"google-refresh-token"`); each `AccountSession`'s store is constructed with
`account: "google-refresh-token#\(accountId)"`. The `service` (`"com.cal-reminder.auth"`) stays
shared — Keychain items are already disambiguated by `(service, account)`, so no new service
per Account is needed.

**UserDefaults scoping:** `UserDefaultsCalendarSelectionStore` gains the same treatment — key
`"selectedCalendarIds.\(accountId)"` instead of the fixed `"selectedCalendarIds"`. The list of
connected Accounts itself is a new key, `"connectedAccounts"`, holding JSON-encoded
`[Account]`, ordered by connection order (first connected, first shown — see AYD-007 "Open
questions" on manual reordering).

**Legacy migration, silent and conditional on outcome:** `AccountRegistry.restore()` checks the
legacy keys only when `AccountStore.accounts` is empty (i.e., this is the first launch after
upgrading past the single-account build). Three outcomes:
- **Token resolves** → re-key it under the Account's scoped Keychain entry, copy
  `selectedCalendarIds` → `selectedCalendarIds.<accountId>`, register the Account, delete both
  legacy keys.
- **Token is rejected by Google** (`AuthError.refreshTokenRevoked`) → the session was already
  dead; delete the legacy keys and register nothing. Nothing is lost that wasn't already lost.
- **Network error** → leave both legacy keys untouched and retry the same check on the next
  launch. A transient offline moment must never be the reason a valid, working token gets
  discarded.

## Alternatives & trade-offs
- **Email as the Account id.** Simpler, human-readable in logs and UserDefaults dumps. Rejected:
  a renamed Google Workspace address would then read as a brand-new Account, silently orphaning
  its Keychain entry and Calendar selection and forcing an unnecessary reconnect.
- **A single Keychain `service` string per Account instead of a scoped `account`.** Keychain
  items are already uniquely addressed by `(service, account)` together; splitting on `service`
  instead would work identically but adds a moving part (a generated service string) for no
  benefit over scoping the `account` field, which was already the account-shaped part of the
  query.
- **Force a reconnect instead of migrating.** Considered and explicitly rejected in favor of
  silent migration (user-facing decision, not just a technical one) — see AYD-007's "Decisions
  already taken with the user." Recorded here because the migration's *safety property* (never
  destroy a token on a network hiccup) is the technical decision that matters if this is ever
  revisited.
