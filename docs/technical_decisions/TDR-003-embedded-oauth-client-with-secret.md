---
id: TDR-003
type: tdr
title: Embedded OAuth installed-app client (client_id + client_secret)
status: accepted
updated: 2026-07-16
parents: [SPEC-009]
related: [AYD-003, TDR-001, TDR-002, RNF-10]
superseded_by: null
---

# TDR-003: Embedded OAuth installed-app client (client_id + client_secret)

> Append-only: never rewrite. A new decision = a new TDR that supersedes this one
> (`superseded_by`). Supersedes **TDR-002**.
>
> **Scope addendum (not a change to the decision).** This TDR was reasoned about a personal,
> local-use app, and its "Alternatives" below reject the token-broker as "disproportionate for
> a personal, local-use app." The project scope has since expanded to a **distributed,
> commercial product**, so that rejection no longer holds: protecting the client secret behind
> an app-owned broker is now the target (**RNF-10**, AYD-003). This TDR remains the **current,
> correct shipped state** — the embedded secret is what makes sign-in work today — and stands
> until a **succeeding TDR** implements the broker. The decision below is unchanged; only the
> "for a personal app" framing in the alternatives is superseded by that later direction.

## Context
TDR-002 embedded a **public** Client ID with **no** `client_secret`, on the assumption that
Google treats installed/desktop OAuth clients as pure public clients where PKCE's
`code_verifier` fully replaces the secret. That assumption is **wrong for Google**: its token
endpoint (`https://oauth2.googleapis.com/token`) rejects both the authorization-code exchange
and the refresh-token grant with `{"error":"invalid_request","error_description":"client_secret
is missing."}` when the secret is absent — verified directly against Google with this app's
real Client ID.

The observable symptom was that browser authorization succeeded (the consent + loopback
redirect returned a `code`), but every token exchange and refresh failed, so the app stayed
effectively disconnected: no account email, no Calendars, no Triggers. The failures were
swallowed by `try?`/`catch`, so the menu simply showed empty.

## Decision
`GoogleOAuthConfig` embeds **both** `clientID` and `clientSecret` (`GoogleOAuthConfig
.embedded`), compiled into the binary. `AuthManager` sends `client_secret` on both the
authorization-code exchange and the refresh grant, **alongside** PKCE's `code_verifier`. PKCE
remains — it is an additional protection, not a replacement for the secret in Google's model.

Everything else TDR-002 established is kept: a single app-owned client compiled in (no per-user
JSON file, no disk I/O), so App Review and the App Sandbox are unaffected. Only the false "no
secret" premise is reversed.

## Alternatives & trade-offs
- **Keep sending no secret (TDR-002 as shipped)** — rejected: does not work; Google requires
  the secret. This is the bug this TDR fixes.
- **Move the secret to a server-side token broker the app calls** — rejected for now:
  disproportionate for a personal, local-use app; adds a hosted component and a new failure
  mode. Revisit only if the app ever needs to rotate the secret without shipping a new build.
- **Keep the per-user on-disk JSON (TDR-001)** — still rejected for the same reasons TDR-002
  gave: unreadable under the App Sandbox and unusable by App Review.

## Consequences for RNF-05
RNF-05 ("secrets only in the Keychain, never in plaintext on disk") targets the **user's**
token — the OAuth refresh/access tokens — which remain Keychain-only and untouched by this
decision. The embedded `client_secret` is the **app's own** installed-app credential, which
Google explicitly documents is *not* confidential for installed apps ("The process ... is
considered a public client ... the client secret is obviously not treated as a secret"); it is
trivially extractable from any distributed binary, so embedding it grants no attacker anything
they could not already obtain. It is therefore an accepted trade-off, not an RNF-05 violation.
The only real protection against misuse of the client is the redirect/loopback restriction and
Google's per-user consent — not the secrecy of the secret.
