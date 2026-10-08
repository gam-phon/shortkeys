#!/bin/bash
# Packages build/Shortkeys.app (run ./build.sh first) into dist/:
#   Shortkeys-<version>.pkg   installer that puts Shortkeys in /Applications
#   Shortkeys-<version>.zip   the app itself
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Shortkeys.app"
[ -d "$APP" ] || { echo "Run ./build.sh first." >&2; exit 1; }
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"

rm -rf dist
mkdir -p dist
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir "$TMP/root"
ditto "$APP" "$TMP/root/Shortkeys.app"

# Not relocatable: otherwise the installer "updates" any other copy of the app
# it finds (e.g. a build folder) instead of installing into /Applications.
pkgbuild --analyze --root "$TMP/root" "$TMP/components.plist" >/dev/null
plutil -replace 0.BundleIsRelocatable -bool NO "$TMP/components.plist"

pkgbuild --root "$TMP/root" --component-plist "$TMP/components.plist" \
    --install-location /Applications \
    --identifier com.yaser.shortkeys.pkg --version "$VERSION" \
    "dist/Shortkeys-$VERSION.pkg"
ditto -c -k --keepParent "$APP" "dist/Shortkeys-$VERSION.zip"
(cd dist && shasum -a 256 Shortkeys-* > SHA256SUMS.txt)
ls -lh dist
