---
id: SPEC-009
type: spec
status: done
parents: [AYD-003]
related: [GLO, TDR-001, TDR-002, TDR-003]
updated: 2026-07-16
---

# SPEC-009: Embedded OAuth public client — what + how

> Rearchitects `AuthManager`/`GoogleOAuthConfig` off the per-user, on-disk client
> credentials file (TDR-001) onto a single embedded OAuth client (TDR-002).
> Closes the structural half of RNF-07: distribution and App Review no longer depend on a
> reviewer creating Google Cloud credentials. Implements AYD-003; doesn't redefine it.

> **Post-implementation correction ([[TDR-003]]).** As written below, this SPEC dropped
> `client_secret` on the assumption Google's installed-app token endpoint accepts PKCE alone.
> It does not — Google rejects the exchange and refresh with "client_secret is missing", so
> login silently failed. The fix keeps everything here **except** that `GoogleOAuthConfig`
> embeds `clientSecret` too and `AuthManager` sends `client_secret` on both grants (alongside
> PKCE). Read every "no/drop `client_secret`" statement below as superseded by TDR-003.

## What (goal)
Replace `GoogleOAuthConfig.loadFromDisk()` with an embedded, public Client ID compiled into
the app, and drop `client_secret` from both the token-exchange and refresh requests — PKCE's
`code_verifier` is what proves the exchange, per Google's installed-app OAuth model. No
change to the read-only scope, the Keychain-only token storage, or the loopback redirect
flow.

## Acceptance criteria
```gherkin
Scenario: No on-disk credentials file
  Given the app has never had a google-oauth-config.json written
  When the app launches
  Then AuthManager still has a usable OAuth client identity
  And no code path reads from Application Support for OAuth credentials

Scenario: Token exchange carries no client secret
  Given a completed browser authorization
  When AuthManager exchanges the code for tokens
  Then the request body includes client_id and code_verifier
  And the request body does not include client_secret

Scenario: Refresh grant carries no client secret
  Given a stored refresh token
  When AuthManager refreshes an expired access token
  Then the request body includes client_id and refresh_token
  And the request body does not include client_secret

Scenario: Existing auth contract is preserved
  Given the rearchitected AuthManager
  Then the refresh token is still stored only in the Keychain (RNF-05)
  And a 401 still triggers exactly one transparent refresh + retry
  And the requested scopes are still calendar.readonly + userinfo.email only

Scenario: CI stays green
  Given the CI gate (SPEC-007)
  When it builds, tests, and lints the tree with this change
  Then all three steps still pass
```

## How (approach)
`GoogleOAuthConfig` drops `Decodable`, `clientSecret`, `loadFromDisk()`, `defaultConfigURL()`,
and `ConfigError`; it keeps only `clientID` plus the two scope constants, and gains a single
`static let embedded = GoogleOAuthConfig(clientID: "")` — the app's one OAuth client identity,
compiled in rather than read from disk. `AppDelegate` constructs `AuthManager` with
`.embedded` instead of the old `(try? loadFromDisk()) ?? GoogleOAuthConfig(...)` fallback.
`AuthManager.exchangeCodeForTokens` and `refreshAccessToken` drop the `client_secret` form
parameter; everything else (PKCE verifier/challenge, loopback listener, Keychain storage,
401-refresh-retry) is unchanged — this is a credential-source swap, not a new auth flow.

The embedded Client ID ships as an empty placeholder: a real value requires the app owner to
register an OAuth Client ID for this app in Google Cloud Console, which is an operational
step outside this SPEC (the same kind of owner action as `project.yml`'s blank
`DEVELOPMENT_TEAM`, or SPEC-008's privacy-policy hosting URL). This SPEC ships the mechanism;
TDR-002 documents the decision and this gap explicitly.

**Not covered by this SPEC** (owner/operational, not code):
- Registering the real Client ID in Google Cloud Console and filling in `.embedded`.
- Google's `calendar.readonly` restricted-scope verification (brand config, scope
  justification, possibly CASA) — a prerequisite for public distribution, tracked as an open
  question in AYD-003.
- App Store Connect "App Review Information" (demo account credentials, reviewer notes) —
  entered directly in App Store Connect, not a repo artifact.
- `DEVELOPMENT_TEAM` / provisioning — AYD-003's own open question, needs a paid Apple
  Developer account.

## Steps
1. **`GoogleOAuthConfig`**: remove `Decodable`, `clientSecret`, `loadFromDisk()`,
   `defaultConfigURL()`, `ConfigError`; add `static let embedded`.
2. **`AuthManager`**: drop `client_secret` from `exchangeCodeForTokens` and
   `refreshAccessToken`'s form-encoded params.
3. **`AppDelegate`**: construct `AuthManager` with `config: .embedded`.
4. **Tests**: update `AuthManagerTests`' fixture config to the new initializer (no
   `clientSecret`); add a request-body assertion that `client_secret` is absent and
   `code_verifier` is present on the token exchange.
5. **Docs**: `TDR-002` (new) supersedes `TDR-001`; `AYD-003` → `status: approved`,
   `children: [SPEC-009]`; one changelog line.

## Affected files
- `cal-reminder/Auth/GoogleOAuthConfig.swift`
- `cal-reminder/Auth/AuthManager.swift`
- `cal-reminder/App/AppDelegate.swift`
- `cal-reminderTests/AuthManagerTests.swift`
- `docs/technical_decisions/TDR-002-embedded-oauth-public-client.md` *(new)*
- `docs/technical_decisions/TDR-001-google-oauth-client-credentials-storage.md`
  (`status: superseded`, `superseded_by: TDR-002`)
- `docs/design/AYD-003-app-store-distribution-oauth.md`
- `docs/changelog.md`

## Tests
- **Acceptance:** request-body assertions in `AuthManagerTests` (no `client_secret`,
  `code_verifier` present, `client_id` present) cover the token-exchange and refresh
  scenarios; the existing 401-refresh-retry, cached-token, and `userEmail()` tests continue
  to pass unmodified, proving the auth contract survives the credential-source swap. The
  "no on-disk credentials file" scenario is structural (the loader no longer exists in
  source) rather than a runtime test.
- **Unit:** none new beyond the request-body assertion — PKCE derivation and 401-retry
  behavior are already covered by SPEC-002's `AuthManagerTests`.

## Checklist
- [ ] `GoogleOAuthConfig` has no `clientSecret`, no disk I/O, and exposes `.embedded`
- [ ] Token-exchange and refresh requests omit `client_secret` (`AuthManagerTests`)
- [ ] Existing auth contract (Keychain-only token, one 401 retry, scopes) still passes
- [ ] `TDR-002` recorded; `TDR-001` marked `superseded`
- [ ] CI (build/test/lint) stays green on the PR
