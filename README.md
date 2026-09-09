# cal-reminder

A native macOS menu bar app that connects to Google Calendar and flies a little airplane
pulling a banner across the screen — over all windows — at each event's reminder time.

The project is **source-available and sold on trust**: this repository builds and runs a
fully functional app for free, with your own Google OAuth client and no feature gate
(RNF-12). A purchase buys the **Distributed Build** instead — signed, notarized, the
project's own credentials, downloaded as a `.dmg` or via Homebrew, and self-updating
(RF-16, RNF-07). Both builds are the same code; see [Source Build vs Distributed
Build](#source-build-vs-distributed-build).

## Build from source

1. Clone the repository.
2. Run `./scripts/bootstrap.sh` — it creates `Config/Secrets.xcconfig` (gitignored) from the
   tracked example and generates the Xcode project.
3. Open `cal-reminder.xcodeproj` in Xcode and run the `cal-reminder` scheme.

This works with **no Google OAuth client at all**. The app launches, and the menu bar shows
"Setup needed — no Google client" with a link back to this section — no network request is
made to Google until you register a client and add it below.

## Register a Google OAuth client

Google Calendar access needs an OAuth client that is yours — the app never ships one for a
Source Build.

1. In [Google Cloud Console](https://console.cloud.google.com/), create a project (or reuse
   one) and enable the **Google Calendar API**.
2. Configure the **OAuth consent screen** and add two scopes: `calendar.readonly` and
   `userinfo.email`.
3. Create an **OAuth client ID** of type **Desktop app**. Copy the client ID and client
   secret it gives you.
4. Open `Config/Secrets.xcconfig` (created by `bootstrap.sh`) and fill in:
   ```
   GOOGLE_OAUTH_CLIENT_ID = your-client-id.apps.googleusercontent.com
   GOOGLE_OAUTH_CLIENT_SECRET = your-client-secret
   ```
5. Re-run `./scripts/bootstrap.sh` (or just rebuild in Xcode) and connect your account from
   the menu bar.

### A note on publishing status

Google's consent screen has a publishing status that affects you directly:

- **Testing** — the default. Refresh tokens expire after about **7 days**, so the app will
  silently disconnect weekly and ask you to reconnect.
- **Production** — refresh tokens don't expire on that schedule, but sign-in shows an
  "unverified app" warning. Expected and safe to click through for your own Source Build.
- **Internal** — available only on a Google Workspace account; avoids both issues, since the
  app is restricted to your own organization.

Google's exact wording and limits shift over time and are not this project's to promise —
the [Google Cloud Console](https://console.cloud.google.com/) is the authority.

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

**Running the same steps locally** (with the secrets above exported as environment variables and
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
