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
