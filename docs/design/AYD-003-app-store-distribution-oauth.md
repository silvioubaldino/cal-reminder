---
id: AYD-003
type: design
status: approved
updated: 2026-07-16
parents: [RNF-07, REQ-01]
children: [SPEC-009]
related: [GLO, AYD-001, TDR-001, TDR-002]
---

# AYD-003: Mac App Store distribution & OAuth rearchitecture

> Analysis & Design of making the app **distributable through the Mac App Store**. The
> structural half of App Store readiness: the current auth model (per-user OAuth JSON on
> disk, TDR-001) is incompatible with the App Sandbox and with App Review, so it must be
> rearchitected. Signing, provisioning and the archive→App Store Connect pipeline live
> here too. The **mechanical** compliance artifacts (entitlements file, privacy manifest,
> icon, metadata) are **AYD-005**; the CI gate is **AYD-004** — this AYD depends on both
> but does not own them.

## Goal
Meet **RNF-07** (and revisit **RF-01**): ship a build that App Review can install and fully
exercise **with a demo Google account, without the reviewer creating any Google Cloud
credentials**, while keeping the OAuth connection read-only and the token in the Keychain.
This requires replacing `GoogleOAuthConfig.loadFromDisk()` (TDR-001) with a single,
app-owned OAuth **public client** whose Client ID ships with the app, and driving the
Google **restricted-scope** (`calendar.readonly`) verification that a publicly distributed
app requires.

## Affected modules
| Module | Role in this feature | Generated SPEC |
|--------|----------------------|----------------|
| AuthManager | Stop reading `GoogleOAuthConfig` from disk; use the embedded public Client ID; run PKCE **without a client secret** (the correct desktop/native flow) | SPEC-009 |
| GoogleOAuthConfig | Repurpose from "load user JSON" to "provide the embedded Client ID + scopes"; drop `clientSecret` | SPEC-009 |
| LoopbackAuthorizationCodeProvider | Unchanged behavior, but must run under the sandbox (needs the `network.server` entitlement declared in AYD-005) | SPEC-009 |
| Build config (`project.yml`) | Real `DEVELOPMENT_TEAM`, App Store provisioning, `CODE_SIGN_STYLE`, versioning | SPEC-009 |
| (docs) TDR-001 | Superseded by a new TDR documenting the embedded-public-client decision | SPEC-009 |

## Interfaces / contract (source of truth)

**GoogleOAuthConfig** (repurposed — no disk I/O, no secret):
```
struct GoogleOAuthConfig {
    static let clientID: String            // embedded; a native OAuth client ID is not secret
    static let calendarReadOnlyScope = "https://www.googleapis.com/auth/calendar.readonly"
    static let userInfoEmailScope    = "https://www.googleapis.com/auth/userinfo.email"
    // loadFromDisk(...) and clientSecret are REMOVED.
}
```

**AuthManager token exchange** (PKCE public client — the `client_secret` parameter is dropped):
```
POST https://oauth2.googleapis.com/token
    grant_type=authorization_code
    code=<code>
    client_id=<GoogleOAuthConfig.clientID>
    code_verifier=<pkce_verifier>          // proves possession; replaces the secret
    redirect_uri=<loopback redirectURI>
// Same change on the refresh grant: client_id + refresh_token, no client_secret.
```

**Contract invariants preserved:** read-only scope, refresh token only in the Keychain
(RNF-05), loopback redirect (RFC 8252). Only the *credential source* and the *secret* change.

## Affected domain model
- No new glossary term. The **connected account** and its token lifecycle are unchanged; only
  how the app identifies itself to Google changes (embedded public client vs. per-user JSON).

## Flow

**Connect (post-rearchitecture — no on-disk config):**
```mermaid
sequenceDiagram
    participant User
    participant Auth as AuthManager
    participant Loop as LoopbackProvider
    participant G as Google OAuth
    User->>Auth: connect
    Auth->>Loop: requestAuthorizationCode(buildURL[client_id=embedded, PKCE])
    Loop->>G: open browser (consent)
    G-->>Loop: redirect 127.0.0.1?code=…
    Loop-->>Auth: code + redirectURI
    Auth->>G: token exchange (client_id + code_verifier, NO secret)
    G-->>Auth: access + refresh token
    Auth->>Auth: store refresh token in Keychain (RNF-05)
```

## Key design decisions
- **Embedded public Client ID, no secret.** For native/desktop OAuth clients Google does not
  treat the client secret as confidential; PKCE (`code_verifier`) is the actual proof. This
  removes the manual-JSON friction and is the App-Review-testable model. New TDR supersedes
  TDR-001.
- **App Review demo path.** Provide reviewer notes + a demo Google account so App Review can
  connect end-to-end; the airplane Overlay is demonstrable via the existing "Test animation".
- **Google restricted-scope verification is a hard dependency, not a code change.** A public
  app using `calendar.readonly` must pass Google's OAuth verification (brand config, scope
  justification, possibly a CASA security assessment) before it leaves "testing" mode.

## Out of scope / open questions
- **Out:** entitlements file, privacy manifest, icon, Info.plist metadata (→ **AYD-005**); CI
  (→ **AYD-004**); multiple Google accounts (still out, AYD-001); non-MAS notarized DMG.
- **Open — sandbox vs. loopback:** confirm the `network.server` entitlement (AYD-005) lets
  `NWListener` bind an ephemeral loopback port under the sandbox; if App Review objects to the
  loopback server, fall back to a custom-URL-scheme redirect (`com.silvioubaldino.cal-reminder:/`).
- **Open — Google verification timeline:** verification can take weeks and may require a privacy
  policy (AYD-005) and a homepage; sequence it **before** App Store submission.
- **Open — bundle id / Team:** needs a paid Apple Developer account and a real `DEVELOPMENT_TEAM`.
