#!/bin/sh
# Builds and signs the release disk image.
#
# Usage: dmg.sh <path-to-cal-reminder.app> <version>
# Produces build/cal-reminder-<version>.dmg.
#
# Required environment: CODE_SIGN_IDENTITY.
set -eu

APP_PATH="${1:?usage: dmg.sh <path-to-cal-reminder.app> <version>}"
VERSION="${2:?usage: dmg.sh <path-to-cal-reminder.app> <version>}"

if [ -z "${CODE_SIGN_IDENTITY:-}" ]; then
  echo "dmg.sh: missing required environment variable CODE_SIGN_IDENTITY" >&2
  exit 1
fi

DMG_PATH="build/cal-reminder-$VERSION.dmg"
rm -f "$DMG_PATH"

# create-dmg can return a non-zero status from a harmless Finder AppleScript race even
# when the image was written successfully, so the real signal is whether the file exists.
create-dmg \
  --volname "cal-reminder $VERSION" \
  --app-drop-link 450 200 \
  --icon "cal-reminder.app" 150 200 \
  "$DMG_PATH" \
  "$APP_PATH" || true

if [ ! -f "$DMG_PATH" ]; then
  echo "dmg.sh: create-dmg did not produce $DMG_PATH" >&2
  exit 1
fi

codesign --sign "$CODE_SIGN_IDENTITY" --timestamp "$DMG_PATH"

echo "Built $DMG_PATH"
