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

# The App Sandbox forces Sparkle's installer out of process (AYD-010). Three things have to
# hold together, and each one fails silently on its own: the service must be opted into, it
# must live in the framework, and it must not be copied into the app — Sparkle refuses to
# even start the updater if it finds one there. Every signature check above passes regardless.
echo "== sandboxed installer (app) =="
launcher_enabled="$(/usr/libexec/PlistBuddy -c "Print :SUEnableInstallerLauncherService" \
  "$APP_PATH/Contents/Info.plist" 2>/dev/null || true)"
if [ "$launcher_enabled" != "true" ]; then
  echo "verify.sh: SUEnableInstallerLauncherService is not true — a sandboxed build cannot install an update" >&2
  exit 1
fi

XPC_PATH="$APP_PATH/Contents/Frameworks/Sparkle.framework/Versions/Current/XPCServices/Installer.xpc"
if [ ! -d "$XPC_PATH" ]; then
  echo "verify.sh: Sparkle.framework is missing XPCServices/Installer.xpc — the enabled service does not exist" >&2
  exit 1
fi
app_team="$(codesign -dv --verbose=2 "$APP_PATH" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
xpc_team="$(codesign -dv --verbose=2 "$XPC_PATH" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
if [ "$app_team" != "$xpc_team" ]; then
  echo "verify.sh: Installer.xpc is signed by '$xpc_team', not the app's team '$app_team'" >&2
  exit 1
fi

if [ -e "$APP_PATH/Contents/XPCServices" ]; then
  echo "verify.sh: Contents/XPCServices exists — Sparkle refuses to start when its services are bundled in the app" >&2
  exit 1
fi

echo "All release invariants hold."
