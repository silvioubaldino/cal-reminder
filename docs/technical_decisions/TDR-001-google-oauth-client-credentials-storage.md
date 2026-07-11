---
id: TDR-001
type: tdr
title: Google OAuth client credentials storage
status: accepted
updated: 2026-07-11
parents: [SPEC-002]
related: [AYD-001]
superseded_by: null
---

# TDR-001: Google OAuth client credentials storage

> Append-only: never rewrite. A new decision = a new TDR that supersedes this one
> (`superseded_by`). Use TDR for internal technical decisions that don't change a
> feature's design/contract. If the decision changes the design of a feature, it's an
> **AYD** (`docs/design/`), not a TDR.

## Context
`AuthManager` (SPEC-002) needs a Google OAuth Desktop-app **Client ID + Client Secret**
to run the PKCE flow. These are per-user values created manually in Google Cloud Console
(AYD-001 "Google setup") — they must never be committed to git, and this single-part
personal app has no settings UI to enter them (out of MVP scope).

## Decision
`GoogleOAuthConfig.loadFromDisk()` reads a small JSON file the user creates once, at
`~/Library/Application Support/cal-reminder/google-oauth-config.json`:
```json
{ "clientId": "...", "clientSecret": "..." }
```
This avoids bundling the values as an Xcode resource (which would require the file to
exist at build time) or hardcoding them in source. The loader takes an injectable
`FileManager`/`URL` so it stays unit-testable.

## Alternatives & trade-offs
- **Bundled `.plist` resource, committed as a template and gitignored when filled** — rejected:
  Xcode's Copy Bundle Resources phase fails the build if the real (gitignored) file is
  absent, which breaks a fresh clone before the user has credentials.
- **Environment variables via the Xcode scheme** — rejected: scheme files are typically
  committed, so secrets would need a separate untracked scheme, adding friction for a
  single-user app with no CI.
- **Hardcode in source** — rejected: violates RNF-05 in spirit (even though a Desktop
  OAuth client secret isn't fully confidential, checking it into a public/shared repo
  is unnecessary exposure).
