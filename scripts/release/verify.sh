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

echo "All release invariants hold."
