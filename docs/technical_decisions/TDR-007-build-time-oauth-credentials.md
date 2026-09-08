---
id: TDR-007
type: tdr
title: OAuth client credentials injected at build time, never committed
status: accepted
updated: 2026-09-08
parents: [AYD-009]
related: [RNF-10, RNF-12, TDR-003, TDR-001, TDR-002]
superseded_by: null
---

# TDR-007: OAuth client credentials injected at build time, never committed

> Append-only: never rewrite. A new decision = a new TDR that supersedes this one
> (`superseded_by`). **Supersedes TDR-003.**

## Context
TDR-003 compiled the app's `client_id` **and** `client_secret` into `GoogleOAuthConfig.swift` as
tracked source. That was sound under its stated premise — a private repository for a personal app —
and it is what makes sign-in work today (Google's token endpoint rejects installed-app clients that
omit the secret, even with PKCE; that finding stands unchanged).

RNF-12 breaks the premise: the repository becomes **public** so anyone can clone, configure and
build (a Source Build). A live `client_secret` in tracked source is then a disclosure — and
GitHub's secret scanning reports Google credentials to Google, which may revoke the client without
warning, breaking sign-in for every existing install at once.

The credential currently at `cal-reminder/Auth/GoogleOAuthConfig.swift:19` has been in the tree
since 39a8f2f. It must be treated as compromised the moment the repository is published, and it
remains in git history even after it is deleted from `HEAD`.

## Decision
1. **Rotate first.** Create a new OAuth client in Google Cloud and delete the existing one, before
   the repository is published. The old credential is never used again.
2. **The credential leaves tracked source.** `GoogleOAuthConfig` reads `clientID` and `clientSecret`
   from a build-time configuration (an untracked `Secrets.xcconfig`, ignored by git, surfaced to the
   app through `Info.plist` keys), not from a Swift literal.
3. **CI injects it.** The release job writes that configuration from encrypted secrets; it appears
   only in the **Distributed Build**. Build logs must not echo it.
4. **A Source Build supplies its own.** With no configuration present the app builds and runs, and
   says in the menu that it needs a Google OAuth client; the README documents registering one. This
   is the only setup step RNF-12's free path asks for, and it is unavoidable — Google credentials
   are per-project and cannot be shared.
5. **The CI *build* job needs no credential.** It compiles and tests without one, so pull requests
   from forks keep working.

Everything else TDR-003 established is unchanged: a single app-owned installed-app client, PKCE on
every exchange, `client_secret` sent on both the authorization-code and refresh grants, tokens in
the Keychain (RNF-05). Only the credential's *source* changes.

## Alternatives & trade-offs
- **Keep it in tracked source and publish anyway** — rejected: it is a disclosure with a known
  automated consequence (revocation), and it hands anyone a client that can impersonate the app in
  Google's consent screen.
- **Keep the repository private** — rejected: it contradicts RNF-12, which is the point of the
  distribution model.
- **Ship the token broker now** (RNF-10's target, which removes the secret from the binary too) —
  deferred, not rejected: it is a hosted component with its own availability and cost story, and it
  does not address today's urgent problem, which is the *repository*. This TDR is the prerequisite
  step; the broker remains the target and will arrive as a succeeding TDR.
- **Scrub git history** (filter-repo, force-push) — rejected as a *substitute* for rotation, which
  is the only measure that actually works: forks, clones and caches keep the old objects. Optional
  as tidying after rotation.

## Consequences
- A Source Build has one manual setup step; the README owns it.
- The Distributed Build is the only artifact carrying the project's credential — consistent with
  RNF-12, where that convenience is exactly what a purchase buys.
- RNF-10's "must" half is met (nothing secret in the repository); its target half (nothing secret in
  the binary) still requires the broker.
