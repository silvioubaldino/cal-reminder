---
id: SPEC-019
type: spec
status: review
updated: 2026-09-09
parents: [AYD-009, AYD-010]
related: [TDR-006, SPEC-018, SPEC-007, GLO, REQ-01]
---

# SPEC-019: Release pipeline — signing, notarization & the `.dmg` — what + how

> Implements AYD-010's signing configuration and AYD-009's delivery half: a `v*` tag produces a
> **Release** — a Developer ID-signed, notarized, stapled `.dmg` published on GitHub, plus the
> Appcast entry that announces it. Today nothing is signed (`project.yml` has an empty
> `DEVELOPMENT_TEAM`, CI builds with `CODE_SIGNING_ALLOWED=NO`) and the version is hardcoded at
> `0.1` / `1`. Depends on **SPEC-018** for the untracked config the real Team ID lands in.
>
> **Sequencing note:** this SPEC publishes the Appcast, but nothing reads it until **SPEC-020**
> puts Sparkle in the app. The first Release users can auto-update *to* is the first one cut
> after SPEC-020; Releases cut before that are download-only, which is correct and expected.

## What (goal)
1. **Versions come from the tag.** `v1.2.0` → `CFBundleShortVersionString = 1.2.0`, with a
   monotonic `CFBundleVersion` Sparkle can compare.
2. **The build is signed and notarized.** Developer ID Application identity, Hardened Runtime,
   App Sandbox kept (AYD-010), notarized and stapled — so a clean machine opens it with a plain
   double-click.
3. **`.github/workflows/release.yml`** does all of it on a tag, from secrets that never touch the
   repository, and refuses to publish anything that fails verification.
4. **The Appcast entry is signed** with the EdDSA key (TDR-006) and published alongside the `.dmg`.

Out of scope: the app-side updater and the Sparkle XPC entitlements (**SPEC-020**); the landing
page and the Homebrew cask bump (**SPEC-021**).

## Acceptance criteria
```gherkin
Scenario: A tag produces a signed, notarized Release
  Given the tag v1.2.0 is pushed
  When the release workflow runs
  Then a cal-reminder-1.2.0.dmg is published on the GitHub Release
  And codesign --verify --deep --strict accepts the app inside it
  And spctl --assess --type execute accepts the app
  And xcrun stapler validate accepts both the app and the .dmg

Scenario: The version comes from the tag
  Given the tag v1.2.0
  Then CFBundleShortVersionString is 1.2.0
  And CFBundleVersion is greater than the previous Release's

Scenario: A non-monotonic build number fails the release
  Given the computed CFBundleVersion is not greater than the last published one
  Then the workflow fails before publishing anything

Scenario: Verification failure blocks publication
  Given notarization is rejected, or a verification command fails
  Then no GitHub Release is created and no Appcast entry is published

Scenario: The Appcast entry is signed
  Given a .dmg was produced
  Then its appcast item carries a sparkle:edSignature made with the project's private key
  And the appcast is published over HTTPS

Scenario: No secret leaks
  Given the workflow ran to completion
  Then no credential, certificate or key appears in the job log
  And the temporary keychain is deleted even when a step fails

Scenario: The PR gate is unaffected
  Given a pull request from a fork
  Then ci.yml still builds, tests and lints with no secret (SPEC-018)
```

## How (approach)
- **Two workflows, one gate.** `ci.yml` (SPEC-007) stays credential-free and unsigned; the new
  `release.yml` triggers only on `push: tags: v*` and is the only place secrets exist.
- **Version derivation.** `CFBundleShortVersionString` is the tag minus its `v`.
  `CFBundleVersion` is `git rev-list --count HEAD` — deterministic, reproducible from a checkout,
  and monotonic along the branch (a workflow run number is not, if the workflow is ever
  recreated). Both are written into the xcconfig SPEC-018 introduced, so `project.yml` stops
  hardcoding them.
- **Notarization uses an App Store Connect API key**, not an Apple ID plus app-specific password
  — it is not tied to a personal account and rotates on its own. *(Resolves AYD-010's open
  question.)*
- **Notarize the app and the disk image.** Sign the `.app` → notarize + staple it → build the
  `.dmg` → sign it → notarize + staple it. Stapling both keeps the first launch clean whether the
  user drags the app out of the image or gets the app on its own.
- **Verify before publishing, not after.** Every check above runs against the built artifact, and
  the publish steps are the last ones in the job.
- **The keychain is ephemeral.** The certificate is imported into a keychain created for the run
  and deleted in an `if: always()` step.

## Steps
1. **`Config/Secrets.example.xcconfig`** — add the release-time settings, empty:
   `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`, `CODE_SIGN_IDENTITY`.
2. **`project.yml`** — `CFBundleShortVersionString: $(MARKETING_VERSION)` and
   `CFBundleVersion: $(CURRENT_PROJECT_VERSION)` in `info.properties`, replacing the hardcoded
   `"0.1"` / `"1"`; a local default of `0.0.0` / `1` in the example so a Source Build still
   builds. `ENABLE_HARDENED_RUNTIME` stays on; sandbox entitlements are unchanged here.
3. **`scripts/release/build.sh`** — takes the version and build number; writes them plus the
   signing identity and Team ID into `Config/Secrets.xcconfig`; runs `xcodegen generate`,
   `xcodebuild archive -configuration Release`, then `-exportArchive` with an
   `ExportOptions.plist` (`method: developer-id`, `signingStyle: manual`). Kept as a script so it
   is runnable locally with the same inputs as CI.
4. **`scripts/release/notarize.sh`** — `xcrun notarytool submit --wait` against the API key,
   failing on any status other than `Accepted`, then `xcrun stapler staple`. Used for both the
   `.app` (zipped for submission) and the `.dmg`.
5. **`scripts/release/verify.sh`** — the four checks from the acceptance criteria; exits non-zero
   on the first failure. Called before any publish step.
6. **`scripts/release/dmg.sh`** — `create-dmg` with the app and an `/Applications` symlink;
   output `cal-reminder-<version>.dmg`; then `codesign` the image.
7. **`.github/workflows/release.yml`** — `on: push: tags: ['v*']`, `runs-on: macos-14`:
   checkout (full history, for the commit count) → select Xcode (reuse `ci.yml`'s "newest
   installed" step) → `brew install xcodegen create-dmg` → import the certificate into a
   temporary keychain → assert monotonicity against the latest published Release → `build.sh` →
   notarize + staple the app → `dmg.sh` → notarize + staple the `.dmg` → `verify.sh` →
   `generate_appcast` (signing the entry with the EdDSA key) → publish the GitHub Release with
   the `.dmg` → publish the appcast → delete the keychain (`if: always()`).
8. **Repository secrets** (documented in the README's Releasing section):
   `DEVELOPER_ID_CERT_P12` (base64), `DEVELOPER_ID_CERT_PASSWORD`, `APPLE_TEAM_ID`,
   `NOTARY_KEY_P8`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`, `SPARKLE_ED_PRIVATE_KEY`,
   `GOOGLE_OAUTH_CLIENT_ID`, `GOOGLE_OAUTH_CLIENT_SECRET`. Every script reads them from the
   environment and none is echoed; `set -x` is not used.
9. **`README.md`** — a "Releasing" section: the tag convention, the secrets above, and how to run
   the same scripts locally.
10. **`docs/changelog.md`** — one line.

## Affected files
- `.github/workflows/release.yml` (new)
- `scripts/release/{build,dmg,notarize,verify}.sh` (new), `scripts/release/ExportOptions.plist` (new)
- `project.yml`, `Config/Secrets.example.xcconfig`, `README.md`

## Tests
No unit test can cover a signing pipeline; the workflow's own verification **is** the test, and it
gates publication (`verify.sh`). What is checked by hand once, on the first Release, and recorded
in the PR:
- On a Mac that has never run this app: mount the `.dmg`, drag to Applications, double-click →
  opens with no Gatekeeper prompt.
- `codesign -d --entitlements - cal-reminder.app` shows the sandbox and network entitlements and
  no `get-task-allow`.
- The app still connects a Google Account (the injected credentials reached the bundle).
- A deliberately corrupted `.dmg` fails `verify.sh` before anything is published.

## Checklist
- [ ] `v*` tag produces a signed, notarized, stapled `.dmg` on the GitHub Release
- [ ] Version and build number derive from the tag and the commit count; monotonicity enforced
- [ ] `codesign`, `spctl` and `stapler validate` all pass on the published artifact
- [ ] Clean-machine double-click opens with no warning
- [ ] A failed notarization or verification publishes nothing
- [ ] Signed Appcast entry published over HTTPS
- [ ] Temporary keychain deleted on every path; no secret in any log
- [ ] `ci.yml` still green on a fork PR with no secrets
