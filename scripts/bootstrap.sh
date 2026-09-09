#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

cp -n Config/Secrets.example.xcconfig Config/Secrets.xcconfig
xcodegen generate
