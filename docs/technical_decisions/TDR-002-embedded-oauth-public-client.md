---
id: TDR-002
type: tdr
title: Embedded OAuth public client (no client secret)
status: superseded
updated: 2026-07-16
parents: [SPEC-009]
related: [AYD-003, TDR-001, TDR-003]
superseded_by: TDR-003
---

# TDR-002: Embedded OAuth public client (no client secret)

> Append-only: never rewrite. A new decision = a new TDR that supersedes this one
> (`superseded_by`). Supersedes **TDR-001**.
>
> **Superseded by [[TDR-003]]:** this TDR's core premise — that Google's installed-app token
> endpoint works with PKCE and *no* `client_secret` — is factually wrong; Google rejects the
> exchange and refresh with "client_secret is missing." TDR-003 re-adds the embedded
> `client_secret` while keeping the embedded, no-disk-file model.

## Context
TDR-001 had `AuthManager` load a per-user `clientId`/`clientSecret` JSON file from
`~/Library/Application Support`, created manually by the user in Google Cloud Console. That
model breaks two RNF-07 requirements: it is unreadable once the app runs under the App
Sandbox (AYD-005 — a sandboxed process is redirected to its own isolated Application Support
directory), and it cannot be exercised by App Review, which has no way to create or receive
per-user Google Cloud credentials.

## Decision
`GoogleOAuthConfig` now ships a single **embedded, public** Client ID (`GoogleOAuthConfig
.embedded`) compiled into the binary — no `clientSecret` field, no disk I/O. This is Google's
documented model for installed/desktop apps: the Client ID is not confidential (the app
cannot keep it secret once distributed), and `AuthManager`'s existing PKCE `code_verifier` is
what actually proves the token exchange came from this app instance, not a shared secret.
Both the authorization-code exchange and the refresh-token grant drop `client_secret`
entirely; nothing else about the flow (loopback redirect, Keychain-only token storage,
`calendar.readonly` scope) changes.

The embedded Client ID value itself is a placeholder (`""`) until the app owner registers a
real OAuth Client ID in Google Cloud Console and fills it in — a one-time operational step
outside this change, comparable to `project.yml`'s blank `DEVELOPMENT_TEAM` (AYD-003's own
open question).

## Alternatives & trade-offs
- **Keep the per-user JSON file, exempt it via a sandbox exception entitlement** — rejected:
  Apple does not grant broad file-system exceptions to MAS apps, and it still leaves App
  Review with no way to supply credentials.
- **Ship the client secret embedded too** — rejected: unnecessary; Google's PKCE flow does
  not need it for installed apps, and treating it as a secret when the binary makes it
  trivially extractable would be misleading, not more secure.
- **Custom URL scheme redirect instead of the loopback listener** — considered (AYD-003's
  open question) but not adopted here: the loopback approach already works and only needs
  the `network.server` entitlement (already granted in AYD-005); revisit only if App Review
  objects to the loopback listener under sandbox.
