---
id: SPEC-008
type: spec
status: review
parents: [AYD-005]   # superseded by AYD-010 — this SPEC is under review
related: [GLO, CONV]
updated: 2026-09-08
---

# SPEC-008: App Sandbox & privacy compliance artifacts — what + how

> **Under review (2026-09-08).** Its parent AYD-005 was superseded by **AYD-010**: the Mac App
> Store target is withdrawn (AYD-009), so this SPEC's App Review-driven criteria no longer apply
> and its signing/notarization half is now owned by SPEC-019. The artifacts it already delivered
> (entitlements, privacy manifest, icon, privacy policy) stand — see AYD-010 for what survives.
>
> Adds the App Sandbox entitlements, privacy manifest, app icon, and bundle metadata a Mac
> App Store submission needs. Closes RNF-08 (and reinforces RNF-05). Implements AYD-005;
> doesn't redefine it. **Artifacts only** — no app behavior changes.

## What (goal)
Ship the compliance wrappers around the existing app: App Sandbox entitlements (least
privilege), a `PrivacyInfo.xcprivacy` privacy manifest, a full `AppIcon` asset set, real
bundle metadata (category, copyright), Hardened Runtime, and a public privacy-policy
document.

## Acceptance criteria
```gherkin
Scenario: App Sandbox is declared, least privilege
  Given cal-reminder.entitlements
  Then com.apple.security.app-sandbox is true
  And only network.client and network.server are additionally granted
  And no file-access, camera, mic, or location entitlement is present

Scenario: Privacy manifest declares required-reason API usage
  Given PrivacyInfo.xcprivacy is bundled with the app
  Then it declares NSPrivacyTracking = false
  And it declares the UserDefaults required-reason API (CA92.1)
  And it declares the connected account's email as collected, app-functionality only, not
    used for tracking

Scenario: App icon renders at every required size
  Given AppIcon.appiconset
  Then it provides all 10 standard macOS icon sizes (16pt–512pt, 1x/2x) including the
    1024×1024 master

Scenario: Bundle metadata is real
  Given the built app
  Then LSApplicationCategoryType is public.app-category.productivity
  And NSHumanReadableCopyright is non-empty
  And Hardened Runtime is enabled

Scenario: CI stays green
  Given the CI gate (SPEC-007)
  When it builds, tests, and lints the tree with these artifacts added
  Then all three steps still pass (CODE_SIGNING_ALLOWED=NO, so the sandbox/entitlements
    are wired but not enforced without a real Team — that's AYD-003)
```

## How (approach)
Pure artifacts/config, no `cal-reminder/*.swift` changes. `project.yml` gets
`CODE_SIGN_ENTITLEMENTS`, `ENABLE_HARDENED_RUNTIME: true`, and the `LSApplicationCategoryType`
/ `NSHumanReadableCopyright` info properties; the checked-in `.xcodeproj` is hand-synced to
match (it's regenerated from `project.yml` on every CI run per AYD-004, but kept in sync for
anyone opening it directly in Xcode). The `AppIcon` is derived from the existing `airplane`
artwork (AYD-005's open question, resolved: reuse existing art over a new mark) composited
on a rounded gradient background, exported at all 10 standard sizes from a 1024×1024 master.

One deliberate refinement from AYD-005's sketch: the privacy manifest declares the
**account email** as collected data (a real Apple-defined type,
`NSPrivacyCollectedDataTypeEmailAddress`), but **not** a made-up "Calendar events" type —
Apple's collected-data types cover data sent off-device to the developer or a third party;
calendar Events are fetched directly from Google with the user's own token and rendered
locally, never transmitted onward, so they don't fit that definition. This doesn't change
the design (still "declare data use to Apple"), just corrects the placeholder key name to a
real one.

## Steps
1. **Entitlements** (new, `cal-reminder/App/cal-reminder.entitlements`): app-sandbox,
   network.client, network.server only.
2. **Privacy manifest** (new, `cal-reminder/App/PrivacyInfo.xcprivacy`): tracking = false;
   collected data type = email address (linked, not tracking, app-functionality); accessed
   API type = UserDefaults (CA92.1, for FlightSpeed/BannerColor/CalendarSelection).
3. **App icon** (new, `cal-reminder/Assets.xcassets/AppIcon.appiconset`): 1024×1024 master
   (existing airplane art on a rounded gradient background) exported at all 10 required
   mac sizes + `Contents.json`.
4. **Bundle metadata** (`project.yml` + checked-in `Info.plist`/`.xcodeproj`):
   `LSApplicationCategoryType`, real `NSHumanReadableCopyright`, `ENABLE_HARDENED_RUNTIME:
   true`, `CODE_SIGN_ENTITLEMENTS` pointing at the new entitlements file,
   `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`.
5. **Privacy policy** (new, `docs/privacy-policy.md`): plain-language policy covering what's
   accessed (Calendar, email), what's stored (Keychain token, local preferences), and that
   nothing is sold/shared/tracked. Hosting the public URL (e.g. GitHub Pages) is a repo
   setting for the owner to flip — not a git change.
6. **Docs**: mark AYD-005 `children: [SPEC-008]`, `status: approved`; add one changelog line;
   set this SPEC `done` once CI is green on the PR.

## Affected files
- `cal-reminder/App/cal-reminder.entitlements` *(new)*
- `cal-reminder/App/PrivacyInfo.xcprivacy` *(new)*
- `cal-reminder/Assets.xcassets/AppIcon.appiconset/*` *(new)*
- `cal-reminder/App/Info.plist`
- `project.yml`
- `cal-reminder.xcodeproj/project.pbxproj` (hand-synced to `project.yml`)
- `docs/privacy-policy.md` *(new)*
- `docs/design/AYD-005-sandbox-privacy-compliance.md`
- `docs/changelog.md`

No `cal-reminder/*.swift` changes — this SPEC ships wrappers, not behavior. Actually
enabling the App Sandbox at runtime (which would move `GoogleOAuthConfig`'s config file off
`~/Library/Application Support` per AYD-005's own noted assumption) is **AYD-003**'s job;
until it lands, a real signed+sandboxed build of this app will not find that file — a known,
already-documented gap, not something this SPEC papers over.

## Tests
- **Acceptance:** the five Gherkin scenarios above are verified by (a) inspecting the
  committed artifacts' contents directly (entitlements keys, manifest keys, icon set
  completeness, metadata values) and (b) the CI gate (SPEC-007) staying green on this PR —
  build/test/lint with `CODE_SIGNING_ALLOWED=NO`, so signing-dependent sandbox enforcement
  itself isn't exercised here (no Apple Team in CI; that's AYD-003).
- **Unit:** none — no app logic changed.

## Checklist
- [ ] `cal-reminder.entitlements` has exactly app-sandbox + network.client + network.server
- [ ] `PrivacyInfo.xcprivacy` declares tracking=false, email collection, UserDefaults reason
- [ ] `AppIcon.appiconset` has all 10 sizes + `Contents.json`
- [ ] `LSApplicationCategoryType`, `NSHumanReadableCopyright`, Hardened Runtime wired
- [ ] CI (build/test/lint) stays green on the PR
- [ ] Privacy-policy URL hosting (GitHub Pages or similar) — repo setting, noted for the owner
