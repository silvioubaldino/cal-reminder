#!/bin/sh
# Archives and exports a Developer ID-signed Release build.
#
# Usage: build.sh <version> <build-number>
#   version      MARKETING_VERSION, e.g. "1.2.0" (the tag minus its leading "v")
#   build-number CURRENT_PROJECT_VERSION, e.g. "312" (git rev-list --count HEAD)
#
# Reads signing identity, team, and Google OAuth credentials from the environment
# (never echoed) and writes them into the untracked Config/Secrets.xcconfig, so the
# Distributed Build carries the project's own credentials (TDR-007).
#
# Required environment: DEVELOPMENT_TEAM, CODE_SIGN_IDENTITY, GOOGLE_OAUTH_CLIENT_ID,
# GOOGLE_OAUTH_CLIENT_SECRET.
set -eu

cd "$(dirname "$0")/../.."

VERSION="${1:?usage: build.sh <version> <build-number>}"
BUILD_NUMBER="${2:?usage: build.sh <version> <build-number>}"

for var in DEVELOPMENT_TEAM CODE_SIGN_IDENTITY GOOGLE_OAUTH_CLIENT_ID GOOGLE_OAUTH_CLIENT_SECRET; do
  eval "value=\${$var:-}"
  if [ -z "$value" ]; then
    echo "build.sh: missing required environment variable $var" >&2
    exit 1
  fi
done

BUILD_DIR="build"
ARCHIVE_PATH="$BUILD_DIR/cal-reminder.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
EXPORT_OPTIONS="$BUILD_DIR/ExportOptions.plist"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

cat > Config/Secrets.xcconfig <<EOF
GOOGLE_OAUTH_CLIENT_ID = $GOOGLE_OAUTH_CLIENT_ID
GOOGLE_OAUTH_CLIENT_SECRET = $GOOGLE_OAUTH_CLIENT_SECRET
DEVELOPMENT_TEAM = $DEVELOPMENT_TEAM
CODE_SIGN_IDENTITY = $CODE_SIGN_IDENTITY
MARKETING_VERSION = $VERSION
CURRENT_PROJECT_VERSION = $BUILD_NUMBER
EOF

xcodegen generate

sed \
  -e "s/__DEVELOPMENT_TEAM__/$DEVELOPMENT_TEAM/" \
  -e "s/__CODE_SIGN_IDENTITY__/$CODE_SIGN_IDENTITY/" \
  scripts/release/ExportOptions.plist > "$EXPORT_OPTIONS"

xcodebuild archive \
  -scheme cal-reminder \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  -destination 'generic/platform=macOS' \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY" \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM"

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS"

echo "Exported $EXPORT_PATH/cal-reminder.app"
