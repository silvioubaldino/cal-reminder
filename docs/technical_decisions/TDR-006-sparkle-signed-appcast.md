---
id: TDR-006
type: tdr
title: Sparkle 2 with an EdDSA-signed Appcast as the update mechanism
status: accepted
updated: 2026-09-08
parents: [AYD-009]
related: [RF-16, RNF-11, AYD-010]
superseded_by: null
---

# TDR-006: Sparkle 2 with an EdDSA-signed Appcast as the update mechanism

> Append-only: never rewrite. A new decision = a new TDR that supersedes this one
> (`superseded_by`).

## Context
RF-16 requires the app to check for and install newer Releases on its own, and RNF-11 requires that
only the project can produce an update the app will accept. The delivery host is a static file
server the project does not operate (GitHub Releases / Pages), so transport security proves only
that the bytes came from that host — not that the project produced them. The app is sandboxed
(AYD-010), which constrains how an updater may install anything.

## Decision
Use **Sparkle 2**, integrated via Swift Package Manager, with an **Appcast signed using EdDSA
(ed25519)**:

- The **public key** is compiled into the app (`SUPublicEDKey` in `Info.plist`); it is the trust
  anchor. The app refuses any download whose `sparkle:edSignature` does not verify against it,
  regardless of where the file came from.
- The **private key** exists in the maintainer's Keychain and as an encrypted CI secret. It never
  enters the repository, a build log, or the download host — so compromising GitHub is not
  sufficient to ship code to a user.
- The Appcast is served over **HTTPS** from the project's domain; `SUFeedURL` and `SUPublicEDKey`
  are absent from a Source Build, which disables the updater entirely (AYD-009).
- Under the App Sandbox, Sparkle's **XPC services** (Downloader and Installer) are embedded and
  reached through the two `mach-lookup.global-name` exceptions declared in AYD-010.
- `generate_appcast` (Sparkle's own tool) produces and signs each entry in the release job; the
  automatic check is **opt-in**, via Sparkle's first-launch prompt.

## Alternatives & trade-offs
- **A hand-rolled updater** (fetch a JSON manifest, download the `.dmg`, verify a SHA-256, swap the
  bundle) — rejected. A checksum published beside the artifact it certifies adds nothing against
  anyone who can write to the host, so it would need its own signature scheme anyway; and the
  sandboxed, relaunch-safe replacement of a running bundle is precisely the part that is hard to
  get right. This is not a place to be original.
- **Sparkle with DSA signatures** (the legacy scheme) — rejected: deprecated, larger keys, and
  Sparkle 2's own guidance is EdDSA.
- **`brew upgrade` as the only update path** — rejected as the mechanism, though it stays supported
  as an install path: it reaches only Homebrew users, requires a manual command, and would leave
  every `.dmg` user (the paying majority) stranded. The cask declares `auto_updates true` so the two
  do not fight (AYD-009).
- **Mac App Store updates** — not available: incompatible with RF-16 by construction (AYD-009).
- **No signature, HTTPS only** — rejected: it makes the download host, which the project does not
  control, a full code-execution authority over every user's machine. This is the requirement
  RNF-11 exists to state.

## Consequences
- One third-party dependency (Sparkle) enters the app, and with it embedded XPC services that must
  be signed as part of the bundle — CI's signing step covers them.
- Losing the private key means no user can be updated again without a manual reinstall; it is backed
  up outside the repository, and rotating it requires shipping a build carrying the new public key.
- The app gains a network call it makes on its own schedule. It is a static-file GET to the project's
  domain and carries no user data, which the privacy policy states.
