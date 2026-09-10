#!/bin/sh
# Runs the Release invariants (AYD-009) against the built artifacts. Exits non-zero on
# the first failing check; nothing downstream publishes if this script fails.
#
# Usage: verify.sh <path-to-cal-reminder.app> <path-to-dmg>
set -eu

APP_PATH="${1:?usage: verify.sh <path-to-cal-reminder.app> <path-to-dmg>}"
DMG_PATH="${2:?usage: verify.sh <path-to-cal-reminder.app> <path-to-dmg>}"

echo "== codesign --verify (app) =="
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "== spctl --assess (app) =="
spctl --assess --type execute --verbose=2 "$APP_PATH"

echo "== stapler validate (app) =="
xcrun stapler validate "$APP_PATH"

echo "== stapler validate (dmg) =="
xcrun stapler validate "$DMG_PATH"

# A Distributed Build with no feed URL or no public key still passes every signature check
# above, but Sparkle disables itself and the Release can never update anyone (RF-16).
echo "== update configuration (app) =="
for key in SUFeedURL SUPublicEDKey; do
  value="$(/usr/libexec/PlistBuddy -c "Print :$key" "$APP_PATH/Contents/Info.plist" 2>/dev/null || true)"
  if [ -z "$value" ]; then
    echo "verify.sh: $key is missing or empty in the built app — the Distributed Build would not self-update" >&2
    exit 1
  fi
done
case "$(/usr/libexec/PlistBuddy -c "Print :SUFeedURL" "$APP_PATH/Contents/Info.plist")" in
  https://*) ;;
  *)
    echo "verify.sh: SUFeedURL must be an https:// URL (RNF-11)" >&2
    exit 1
    ;;
esac

# The App Sandbox forces Sparkle's installer out of process (AYD-010). Without its XPC
# service in the bundle the mach-lookup fails and every update dies at install time — while
# every signature check above still passes.
echo "== sandboxed installer (app) =="
XPC_PATH="$APP_PATH/Contents/XPCServices/Installer.xpc"
if [ ! -d "$XPC_PATH" ]; then
  echo "verify.sh: Contents/XPCServices/Installer.xpc is missing — a sandboxed build cannot install an update" >&2
  exit 1
fi
app_team="$(codesign -dv --verbose=2 "$APP_PATH" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
xpc_team="$(codesign -dv --verbose=2 "$XPC_PATH" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
if [ "$app_team" != "$xpc_team" ]; then
  echo "verify.sh: Installer.xpc is signed by '$xpc_team', not the app's team '$app_team'" >&2
  exit 1
fi

echo "All release invariants hold."
