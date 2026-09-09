#!/bin/sh
# Single documented entry point for building cal-reminder. Idempotent: never
# overwrites an existing Config/Secrets.xcconfig. Safe to run with no Google
# OAuth client at all — the app builds and runs, just unconfigured (SPEC-018).
set -eu

cd "$(dirname "$0")/.."

cp -n Config/Secrets.example.xcconfig Config/Secrets.xcconfig
xcodegen generate
