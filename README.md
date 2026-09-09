# cal-reminder

A native macOS menu bar app that connects to Google Calendar and flies a little airplane
pulling a banner across the screen — over all windows — at each event's reminder time.

The code is published under an open license ([PolyForm Shield 1.0.0](LICENSE.md)): you're
free to clone it, adapt it, and run your own build for any purpose that doesn't compete with
this project. A purchase buys the **Distributed Build** instead — signed, notarized, the
project's own Google credentials, downloaded as a `.dmg` or via Homebrew, and self-updating
(RF-16, RNF-07). Both builds are the same code; see [Source Build vs Distributed
Build](#source-build-vs-distributed-build).

## Build from source

1. Clone the repository.
2. Run `./scripts/bootstrap.sh` — it creates `Config/Secrets.xcconfig` (gitignored) from the
   tracked example and generates the Xcode project.
3. Open `cal-reminder.xcodeproj` in Xcode and run the `cal-reminder` scheme.

This works with **no Google OAuth client at all**. The app launches, and the menu bar shows
"Setup needed — no Google client" until you register your own (see below) — no network
request is made to Google before that.

## Google OAuth client

Calendar access needs an OAuth client that is yours — the app never ships one for a Source
Build. Create one in [Google Cloud Console](https://console.cloud.google.com/) with
read-only Calendar access, then put its id and secret in `Config/Secrets.xcconfig`
(`GOOGLE_OAUTH_CLIENT_ID` / `GOOGLE_OAUTH_CLIENT_SECRET`). Google's own console and
documentation are the reference for setting one up and for how its publishing status
affects token lifetime.

## Releasing

Pushing a tag matching `v*` (e.g. `v1.2.0`) runs `.github/workflows/release.yml`, which builds,
signs, notarizes and publishes the Distributed Build — nobody needs to do this by hand. It is the
only workflow that touches secrets; `ci.yml` (build/test/lint on every push and PR) stays
credential-free.

**What the tag drives:**
- `CFBundleShortVersionString` is the tag minus its `v` (`v1.2.0` → `1.2.0`).
- `CFBundleVersion` is `git rev-list --count HEAD` at that tag — deterministic and monotonic
  along the branch; the workflow refuses to publish a Release whose build number does not exceed
  the last published one.

**Repository secrets** the workflow expects (Settings → Secrets and variables → Actions):

| Secret | Purpose |
|---|---|
| `DEVELOPER_ID_CERT_P12` | Base64-encoded Developer ID Application certificate + private key |
| `DEVELOPER_ID_CERT_PASSWORD` | Password protecting that `.p12` |
| `APPLE_TEAM_ID` | Apple Developer Team ID |
| `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`, `NOTARY_KEY_P8` | App Store Connect API key used by `notarytool` |
| `SPARKLE_ED_PRIVATE_KEY` | EdDSA private key that signs each Appcast entry (TDR-006) |
| `GOOGLE_OAUTH_CLIENT_ID`, `GOOGLE_OAUTH_CLIENT_SECRET` | The project's own OAuth client, injected only into the Distributed Build (TDR-007) |

None of these ever reaches the repository, a build log, or a Source Build.

**Repository variables** the workflow expects (Settings → Secrets and variables → Actions →
Variables). These are deliberately *not* secrets — the app ships both of them in its `Info.plist`,
and the public key is the update trust anchor anyone can inspect (RNF-11):

| Variable | Purpose |
|---|---|
| `SPARKLE_FEED_URL` | `https://` URL the app reads the Appcast from, e.g. `https://silvioubaldino.github.io/cal-reminder/appcast.xml` |
| `SPARKLE_PUBLIC_ED_KEY` | Base64 EdDSA public key matching `SPARKLE_ED_PRIVATE_KEY` |

`verify.sh` refuses to publish a Release whose app carries neither, so a build that could never
update anyone cannot reach a user.

**Running the same steps locally** (with the secrets and variables above exported as environment variables and
a Developer ID certificate in your login keychain):
```
scripts/release/build.sh <version> <build-number>       # archive + export
scripts/release/notarize.sh build/export/cal-reminder.app
scripts/release/dmg.sh build/export/cal-reminder.app <version>
scripts/release/notarize.sh build/cal-reminder-<version>.dmg
scripts/release/verify.sh build/export/cal-reminder.app build/cal-reminder-<version>.dmg
```
`verify.sh` runs the same checks (`codesign --verify`, `spctl --assess`, `stapler validate`) the
workflow uses as its publish gate.

## Source Build vs Distributed Build

| | Source Build | Distributed Build |
|---|---|---|
| Features | Identical | Identical |
| Google OAuth client | Yours | The project's |
| Signed & notarized | No | Yes |
| Self-updates (RF-16) | Never | Yes |
| Cost | Free | Purchase |

Building from source is never a lesser version of the app — it's the same code, with your
own credentials instead of a purchase.

A Source Build never checks for updates: it has no feed it can safely trust, and pointing it at
the project's own would silently replace your build — Google client and all — with the
project's. The menu says "Updates: source build" instead of hiding the control.
