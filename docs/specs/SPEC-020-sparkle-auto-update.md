---
id: SPEC-020
type: spec
status: draft
updated: 2026-09-08
parents: [AYD-009]
related: [TDR-006, AYD-010, SPEC-018, SPEC-019, GLO, REQ-01]
---

# SPEC-020: Auto-update in the app — what + how

> Implements **RF-16** and the app half of AYD-009: Sparkle 2 reads the signed Appcast SPEC-019
> publishes, verifies each Release against the public key compiled into the binary (RNF-11), and
> installs it with the user's consent. Also the point where a **Source Build** visibly, and
> deliberately, has no updater. Depends on SPEC-018 (the config the keys ride in) and SPEC-019
> (something to update to).

## What (goal)
1. **Sparkle 2 is embedded**, with its XPC services so it works under the App Sandbox AYD-010
   keeps, and the two entitlements those services need.
2. **`UpdateController`** implements AYD-009's `Updating` contract: configured or not, automatic
   checks on or off, a user-initiated check.
3. **The menu** states the running version, offers "Check for updates…" and "Check
   automatically", and in a Source Build says so instead of pretending.
4. **An unverifiable update is refused** — the guarantee is Sparkle's signature check against
   `SUPublicEDKey`, which this SPEC wires but does not reimplement.

## Acceptance criteria
```gherkin
Scenario: A configured build offers updates
  Given the bundle carries a feed URL and a public key
  When the user opens the menu
  Then it shows "cal-reminder <version>"
  And "Check for updates…" is enabled
  And "Check automatically" reflects the stored preference

Scenario: A Source Build has no updater
  Given the bundle carries no feed URL or no public key
  Then the menu reads "Updates: source build"
  And "Check for updates…" is absent
  And no request is made to any feed

Scenario: Automatic checks are off until the user asks
  Given a freshly installed app whose preference was never set
  Then automaticallyChecksForUpdates is false
  And no scheduled check runs

Scenario: The preference persists
  Given the user turns "Check automatically" on
  When the app restarts
  Then it is still on and a scheduled check may run

Scenario: A user-initiated check brings its window forward
  Given the app is a background agent with no Dock icon
  When the user clicks "Check for updates…"
  Then Sparkle's window is visible and frontmost

Scenario: A background check never steals focus
  Given automatic checks are on
  When a scheduled check finds nothing
  Then the app is never activated and nothing appears on screen

Scenario: An update that does not verify is refused
  Given an Appcast entry whose signature does not match the embedded public key
  Then Sparkle refuses it and the app stays on its current version
```

## How (approach)
- **Keys ride the same road as the OAuth credentials** (SPEC-018): `SUFeedURL` and
  `SUPublicEDKey` expand from xcconfig variables into `Info.plist`, empty in the tracked example.
  So "Source Build" needs no flag and no build configuration of its own — it is simply the build
  where those two values are absent, exactly as AYD-009 describes.
- **`isConfigured` is a pure function** over the two strings (non-empty after trimming), tested
  without a bundle, mirroring `GoogleOAuthConfig.make` from SPEC-018.
- **The updater is wrapped, not exposed.** `UpdateController` owns the
  `SPUStandardUpdaterController` and is the only type that imports Sparkle; the menu talks to the
  `Updating` protocol, so `StatusMenuController` stays testable with a fake.
- **Automatic checks default to off**, driven by the app's own `UserDefaults`-backed store — the
  pattern the repo already uses for Flight Speed, Banner color and Reminder settings — rather than
  Sparkle's first-launch permission dialog. This satisfies RF-16's "opt-in" (the check never runs
  until the user asks for it) without an unprompted dialog appearing over whatever the user was
  doing, which for an `LSUIElement` agent reads as a glitch.
- **Activation is scoped to the user-initiated path.** `NSApp.activate(ignoringOtherApps: true)`
  is called only from "Check for updates…", never from a scheduled check. RNF-02's no-focus-stealing
  rule is about the Overlay, but its spirit is the reason this is one-directional.
- **Sandbox wiring.** Sparkle's Downloader and Installer XPC services are embedded in the bundle
  and reached through `com.apple.security.temporary-exception.mach-lookup.global-name` for
  `$(PRODUCT_BUNDLE_IDENTIFIER)-spks` and `-spki` (AYD-010's contract). They are added here, with
  Sparkle, rather than in SPEC-019 — an entitlement naming services the bundle does not contain
  would be dead configuration.

## Steps
1. **`project.yml`** — add the Sparkle SPM package (2.x, exact version pinned) and the dependency
   on the app target; ensure its XPC services are embedded and signed with the app; add
   `SUFeedURL: $(SPARKLE_FEED_URL)`, `SUPublicEDKey: $(SPARKLE_PUBLIC_ED_KEY)` and
   `SUScheduledCheckInterval: 86400` to `info.properties`.
2. **`Config/Secrets.example.xcconfig`** — add `SPARKLE_FEED_URL` and `SPARKLE_PUBLIC_ED_KEY`,
   empty. *(The feed URL and public key are not secret; they live here because this is the file
   that already differs between a Source Build and a Distributed Build.)*
3. **`cal-reminder/App/cal-reminder.entitlements`** — add the two `mach-lookup.global-name`
   exceptions. Nothing else changes: no file, camera, mic or location access (AYD-010).
4. **`cal-reminder/Update/UpdateSettings.swift`** (new) — `UpdateSettingsStoring` with
   `automaticallyChecks: Bool` (default `false`) and its `UserDefaults` implementation, alongside
   the existing stores.
5. **`cal-reminder/Update/UpdateController.swift`** (new) — `Updating` protocol per AYD-009 plus
   the Sparkle-backed implementation and `UpdateConfiguration.make(feedURL:publicKey:)`. When
   unconfigured it constructs no updater at all, so there is no object that could make a request.
6. **`AppState.swift`** — add `var updateStatus: UpdateStatus` (`.configured(version: String)` /
   `.sourceBuild`), rendered by the menu the same way every other state is.
7. **`StatusMenuController.swift`** — a version row plus "Check for updates…" and a "Check
   automatically" checkbox in the configured case; a single disabled "Updates: source build" row
   otherwise.
8. **`AppDelegate.swift`** — build the `UpdateController` from the bundle values, hand it to the
   menu controller, and set `state.updateStatus`.
9. **`.swiftlint.yml`** — exclude Sparkle's checkout from linting if SPM's path is picked up by
   the `included:` globs.
10. **`README.md`** — a paragraph in the Source Build section: no self-update, and why (no feed it
    can safely trust — pointing it at the project's would replace the user's own build).
11. **`docs/changelog.md`** — one line.

## Affected files
- `cal-reminder/Update/{UpdateController,UpdateSettings}.swift` (new)
- `cal-reminder/App/{AppState,AppDelegate}.swift`, `cal-reminder/App/cal-reminder.entitlements`
- `cal-reminder/MenuBar/StatusMenuController.swift`
- `cal-reminderTests/{UpdateControllerTests,UpdateSettingsStoreTests}.swift` (new),
  `cal-reminderTests/AppStateTests.swift`
- `project.yml`, `Config/Secrets.example.xcconfig`, `.swiftlint.yml`, `README.md`

## Tests
- **Acceptance:** `UpdateControllerTests` — `make` yields a configuration for two real values and
  `nil` for missing, empty or whitespace-only ones; `isConfigured == false` means no updater is
  constructed; toggling `automaticallyChecks` writes through to the store and to the updater;
  a user-initiated check calls through, a scheduled one never activates the app (asserted on a
  fake updater recording both). Menu behavior is asserted against a fake `Updating`: the
  configured case shows the version, an enabled check item and the checkbox; the source-build
  case shows one disabled row and no check item.
- **Unit:** `UpdateSettingsStoreTests` — default `false`, round-trips, survives a new instance
  over the same `UserDefaults` suite (the pattern in `SkipOnClickStoreTests`).
- **Not automated:** signature refusal is Sparkle's own guarantee, verified once by hand against
  a deliberately mis-signed Appcast entry on a staging feed, and recorded in the PR. We do not
  reimplement or unit-test Sparkle's cryptography.

## Checklist
- [ ] Sparkle 2 embedded, pinned, with its XPC services signed into the bundle
- [ ] The two `mach-lookup` entitlements added; no other entitlement changed
- [ ] Configured build: version row, working "Check for updates…", persisted "Check automatically"
- [ ] Automatic checks off until the user opts in; no unprompted dialog on first launch
- [ ] Source Build: "Updates: source build", no check item, no network request
- [ ] User-initiated check comes to the front; a scheduled check never activates the app
- [ ] A mis-signed update is refused (manual verification against a staging feed)
- [ ] An update installs end to end from a real Release and relaunches into the new version
