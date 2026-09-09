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
# The Appcast feed URL and EdDSA public key come from the environment too: they are not
# secret, but without them the Distributed Build ships with no update configuration and
# Sparkle disables itself (AYD-009), so they are required rather than optional.
#
# Required environment: DEVELOPMENT_TEAM, CODE_SIGN_IDENTITY, GOOGLE_OAUTH_CLIENT_ID,
# GOOGLE_OAUTH_CLIENT_SECRET, SPARKLE_FEED_URL, SPARKLE_PUBLIC_ED_KEY.
set -eu

cd "$(dirname "$0")/../.."

VERSION="${1:?usage: build.sh <version> <build-number>}"
BUILD_NUMBER="${2:?usage: build.sh <version> <build-number>}"

for var in DEVELOPMENT_TEAM CODE_SIGN_IDENTITY GOOGLE_OAUTH_CLIENT_ID GOOGLE_OAUTH_CLIENT_SECRET \
           SPARKLE_FEED_URL SPARKLE_PUBLIC_ED_KEY; do
  eval "value=\${$var:-}"
  if [ -z "$value" ]; then
    echo "build.sh: missing required environment variable $var" >&2
    exit 1
  fi
done

# An xcconfig treats "//" as a comment, which would truncate an https:// feed URL and can
# also cut a base64 key short. Every "/" is written as $(SLASH) and expanded back by the
# build-setting evaluator when it substitutes the value into Info.plist.
escape_slashes() {
  printf '%s' "$1" | sed 's|/|$(SLASH)|g'
}

FEED_URL_VALUE="$(escape_slashes "$SPARKLE_FEED_URL")"
PUBLIC_ED_KEY_VALUE="$(escape_slashes "$SPARKLE_PUBLIC_ED_KEY")"

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
SLASH = /
SPARKLE_FEED_URL = $FEED_URL_VALUE
SPARKLE_PUBLIC_ED_KEY = $PUBLIC_ED_KEY_VALUE
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
