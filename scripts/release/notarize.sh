#!/bin/sh
# Submits an artifact to Apple's notary service and staples the ticket once accepted.
#
# Usage: notarize.sh <path-to-.app-or-.dmg>
#
# Required environment: NOTARY_KEY_ID, NOTARY_ISSUER_ID, NOTARY_KEY_P8 (the App Store
# Connect API key's .p8 contents). The key is written to a temporary file for the
# duration of the submission and removed afterwards; nothing is echoed.
set -eu

ARTIFACT="${1:?usage: notarize.sh <path-to-.app-or-.dmg>}"

for var in NOTARY_KEY_ID NOTARY_ISSUER_ID NOTARY_KEY_P8; do
  eval "value=\${$var:-}"
  if [ -z "$value" ]; then
    echo "notarize.sh: missing required environment variable $var" >&2
    exit 1
  fi
done

KEY_FILE="$(mktemp -t notary-key).p8"
cleanup() { rm -f "$KEY_FILE" "$SUBMISSION" 2>/dev/null || true; }
trap cleanup EXIT

printf '%s' "$NOTARY_KEY_P8" > "$KEY_FILE"
chmod 600 "$KEY_FILE"

case "$ARTIFACT" in
  *.app)
    SUBMISSION="$(mktemp -t notary-submission).zip"
    ditto -c -k --keepParent "$ARTIFACT" "$SUBMISSION"
    ;;
  *.dmg)
    SUBMISSION="$ARTIFACT"
    ;;
  *)
    echo "notarize.sh: unsupported artifact $ARTIFACT (expected .app or .dmg)" >&2
    exit 1
    ;;
esac

xcrun notarytool submit "$SUBMISSION" \
  --key "$KEY_FILE" \
  --key-id "$NOTARY_KEY_ID" \
  --issuer "$NOTARY_ISSUER_ID" \
  --wait

xcrun stapler staple "$ARTIFACT"

echo "Notarized and stapled $ARTIFACT"
