---
id: SPEC-018
type: spec
status: review
updated: 2026-09-09
parents: [AYD-009]
related: [TDR-007, TDR-003, GLO, REQ-01, SPEC-002, SPEC-009]
---

# SPEC-018: OAuth credentials out of the repository — what + how

> Implements the prerequisite slice of AYD-009 (TDR-007). Today
> `GoogleOAuthConfig.swift:19` carries a live `client_secret` in tracked source — correct under
> TDR-003's private-repository premise, a disclosure under RNF-12's public one. This SPEC
> rotates it out of the build, moves both credentials to an untracked build-time configuration,
> and makes the **Source Build** a working, documented path instead of an implied one: a fresh
> clone must build, run, and *say* what it needs. Nothing else about the OAuth flow changes —
> PKCE, the secret on both grants, and Keychain storage are untouched (TDR-003's finding stands).

## What (goal)
Four coordinated changes:
1. **The credential leaves tracked source.** `GoogleOAuthConfig` reads `clientID`/`clientSecret`
   from the bundle (fed by an untracked `Secrets.xcconfig`) and yields `nil` when they are absent.
2. **A missing credential is a legible app state, not a silent failure.** The menu says the app
   needs a Google OAuth client and points at the README; no OAuth call is attempted.
3. **A fresh clone builds with zero setup.** A bootstrap step creates the untracked config from a
   tracked example, so `xcodegen generate && xcodebuild` works with no credential at all — which
   is also what keeps CI (RNF-09) and fork PRs green.
4. **The README documents the Source Build** at a high level — what it needs, not a walkthrough
   of getting it (product decision, see step 10).

The maintainer-side rotation is a prerequisite, not a code change (§Prerequisite).

## Prerequisite (manual, before merge)
Rotate the credential in Google Cloud: create a new OAuth **Desktop app** client, put it in the
maintainer's local `Secrets.xcconfig` and in the CI secrets, then **delete the old client**. The
value at `cal-reminder/Auth/GoogleOAuthConfig.swift:19` stays in git history after this SPEC
deletes it from `HEAD`; rotation — not history rewriting — is what makes that harmless (TDR-007).
Deleting the old client also invalidates every existing install's refresh token, so the first
Release after this change reconnects each Account once (RF-14's per-Account reconnect path,
already built).

## Acceptance criteria
```gherkin
Scenario: No credential in the repository
  Given a clean checkout at HEAD
  When the tracked files are searched for the client id or secret
  Then neither appears in any tracked file
  And Secrets.xcconfig is ignored by git

Scenario: A fresh clone builds and runs with no credential
  Given a clean checkout with no Secrets.xcconfig
  When the bootstrap step runs and the app is built
  Then the build succeeds
  And the app launches without crashing

Scenario: An unconfigured app says so instead of failing silently
  Given the build carries no OAuth client id or secret
  When the user opens the menu
  Then the status reads "Setup needed — no Google client"
  And a "How to set up a Google client…" item opens the README
  And "Add Google account…" is disabled
  And no network request is made to Google

Scenario: A configured build behaves exactly as before
  Given the build carries a client id and secret
  When the user connects an Account
  Then the authorization, exchange and refresh are unchanged from SPEC-009/TDR-003
  And the menu never mentions setup

Scenario: A placeholder value counts as absent
  Given Secrets.xcconfig still holds the example's empty values
  Then the app reports itself unconfigured rather than calling Google with an empty client id

Scenario: CI builds and tests without any credential
  Given the workflow has no OAuth secret available
  When CI runs on a pull request from a fork
  Then bootstrap, build, test and lint all succeed
```

## How (approach)
- **Build settings → `Info.plist` → app.** `Secrets.xcconfig` defines `GOOGLE_OAUTH_CLIENT_ID`
  and `GOOGLE_OAUTH_CLIENT_SECRET` (plus `DEVELOPMENT_TEAM`, see below); `project.yml` wires it
  as the target's config file and adds two `Info.plist` keys expanding those variables. The app
  reads the keys from its own bundle. No disk I/O outside the bundle (the reason TDR-001 was
  dropped stays respected), and no credential in any tracked file.
- **`nil` is the unconfigured state.** `GoogleOAuthConfig.bundled` is `GoogleOAuthConfig?`. The
  parsing rule is a pure function so it is testable without a bundle, and it treats empty and
  whitespace-only values as absent — that is what the tracked example contains, so a
  never-configured clone is unconfigured rather than broken in a confusing way.
- **The state reaches the menu through `AppState`**, the way every other menu state already does
  (`statusTitle`), rather than through a new path in `StatusMenuController`.
- **`DEVELOPMENT_TEAM` moves into the same file.** AYD-010 needs the real Team ID for signing, and
  committing it would break every fresh clone's signing. It lives in `Secrets.xcconfig`, empty in
  the example, which leaves Xcode on automatic signing with whatever personal team the builder has.

## Steps
1. **`Config/Secrets.example.xcconfig`** (tracked) — the three settings with empty values and a
   comment pointing at the README:
   ```
   GOOGLE_OAUTH_CLIENT_ID =
   GOOGLE_OAUTH_CLIENT_SECRET =
   DEVELOPMENT_TEAM =
   ```
2. **`scripts/bootstrap.sh`** (tracked, executable) — `cp -n Config/Secrets.example.xcconfig
   Config/Secrets.xcconfig` then `xcodegen generate`. Idempotent; never overwrites an existing
   file. This is the single documented entry point for building.
3. **`.gitignore`** — add `Config/Secrets.xcconfig`.
4. **`project.yml`** — set the target's `configFiles` (Debug and Release) to
   `Config/Secrets.xcconfig`; add to the target's `info.properties`:
   `GoogleOAuthClientID: $(GOOGLE_OAUTH_CLIENT_ID)` and
   `GoogleOAuthClientSecret: $(GOOGLE_OAUTH_CLIENT_SECRET)`; remove the empty
   `DEVELOPMENT_TEAM: ""` from `settings.base` so the xcconfig supplies it.
5. **`GoogleOAuthConfig.swift`** — delete `static let embedded` and its literals. Add:
   ```swift
   static func make(clientID: String?, clientSecret: String?) -> GoogleOAuthConfig?
   // nil when either is nil, empty, or whitespace-only
   static let bundled: GoogleOAuthConfig? = make(
       clientID: Bundle.main.object(forInfoDictionaryKey: "GoogleOAuthClientID") as? String,
       clientSecret: Bundle.main.object(forInfoDictionaryKey: "GoogleOAuthClientSecret") as? String
   )
   ```
   Update the doc comment: the credential is injected at build time (TDR-007), and the reason
   both values are sent stays TDR-003's.
6. **`AppState.swift`** — add `var oauthConfigured = true`. In `statusTitle`, return
   `"Setup needed — no Google client"` first when it is `false`.
7. **`AppDelegate.swift`** — replace both `config: .embedded` uses with the unwrapped
   `GoogleOAuthConfig.bundled`. When it is `nil`, build the registry with no session factories
   exercised (no Account is connectable) and set `state.oauthConfigured = false` on the
   coordinator before `start()`; skip the initial Poll.
8. **`StatusMenuController.swift`** — when `state.oauthConfigured` is `false`: disable
   "Add Google account…" and insert "How to set up a Google client…" below the status label,
   opening the README URL with `NSWorkspace.shared.open`. Both revert when it is `true`.
9. **`.github/workflows/ci.yml`** — replace the bare `xcodegen generate` with
   `./scripts/bootstrap.sh`. No secret is added to this workflow: the build must stay
   credential-free (the release workflow, SPEC-019, is where CI writes real values).
10. **`README.md`** (new) — §Build from source (clone → `./scripts/bootstrap.sh` → open in Xcode)
    and §Google OAuth client, naming what's needed (a Calendar-readonly OAuth client, its id
    and secret in `Config/Secrets.xcconfig`) without walking through Google Cloud Console
    step by step — that path stays possible, just not spelled out, a deliberate choice to
    keep the free path real without making it the path of least resistance. Close with
    §Source Build vs Distributed Build, restating RNF-12: same features, own credential, no
    self-update.
11. **`docs/changelog.md`** — one line.

## Affected files
- `cal-reminder/Auth/GoogleOAuthConfig.swift`
- `cal-reminder/App/AppDelegate.swift`
- `cal-reminder/App/AppState.swift`
- `cal-reminder/MenuBar/StatusMenuController.swift`
- `cal-reminderTests/GoogleOAuthConfigTests.swift` (new)
- `cal-reminderTests/AppStateTests.swift`
- `project.yml`, `.gitignore`, `.github/workflows/ci.yml`
- `Config/Secrets.example.xcconfig` (new), `scripts/bootstrap.sh` (new), `README.md` (new)

## Tests
- **Acceptance:** `GoogleOAuthConfigTests` — `make` returns a config for two real values, and
  `nil` for each of: missing id, missing secret, empty string, whitespace-only, and the example
  file's own values. `AppStateTests` — `oauthConfigured == false` wins over every other status,
  including when Accounts exist; `true` leaves `statusTitle` exactly as it is today (the existing
  cases must still pass unchanged).
- **Unit:** `AuthManagerTests` keeps constructing `GoogleOAuthConfig` directly and needs no
  change — proof that the contract seen by the OAuth code is unchanged.
- **Not automated:** the "no credential in tracked files" and "fresh clone builds" criteria are
  checked by `git grep` and a clean clone in the review of this PR; adding a CI grep for a
  rotated-away secret is not worth a job.

## Checklist
- [ ] Old OAuth client rotated and deleted in Google Cloud (prerequisite — maintainer action,
      outside this PR; do not merge to a public remote before this is done)
- [x] No client id or secret in any tracked file; `Config/Secrets.xcconfig` gitignored
- [ ] A clean clone builds and runs after `./scripts/bootstrap.sh`, with no credential
      (needs a macOS CI run to confirm — implemented, not yet observed green)
- [x] Unconfigured build states it in the menu, links the README, disables adding an Account, and
      makes no request to Google
- [x] Configured build connects, polls and refreshes exactly as before (code path unchanged,
      only the credential source moved)
- [x] `DEVELOPMENT_TEAM` no longer tracked; automatic signing still works on a fresh clone
- [ ] CI green without any OAuth secret (pending a run on the PR)
- [x] README names what's needed for a Google OAuth client, without a full walkthrough (product decision, see step 10)
