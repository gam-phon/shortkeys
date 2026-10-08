#!/bin/bash
# Builds Shortkeys.app into ./build and signs it with a stable identity.
#   SIGN_IDENTITY="Apple Development: you@example.com (TEAMID)" ./build.sh
#   VERSION=1.2.0 BUILD_NUMBER=42 ./build.sh   # stamps the app's version (CI does this)
set -euo pipefail
cd "$(dirname "$0")"

SIGN_IDENTITY="${SIGN_IDENTITY:-Shortkeys Dev}"
# Build against the macOS 27 SDK (override with SDKROOT=...).
export SDKROOT="${SDKROOT:-$(xcrun --sdk macosx27.0 --show-sdk-path 2>/dev/null || xcrun --sdk macosx --show-sdk-path)}"
echo "SDK: $SDKROOT"
APP="build/Shortkeys.app"
# Assemble and sign a staging copy; only a fully signed app replaces $APP,
# so a failed build never leaves a broken (unsigned) app behind.
STAGE="build/.staging/Shortkeys.app"

swift build -c release --arch arm64 "$@"
BIN="$(swift build -c release --arch arm64 --show-bin-path)"

rm -rf build/.staging
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp Resources/Info.plist "$STAGE/Contents/Info.plist"
if [ -n "${VERSION:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$STAGE/Contents/Info.plist"
fi
if [ -n "${BUILD_NUMBER:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$STAGE/Contents/Info.plist"
fi
cp "$BIN/Shortkeys" "$STAGE/Contents/MacOS/Shortkeys"
if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns "$STAGE/Contents/Resources/"
fi
for bundle in "$BIN"/*.bundle; do
    if [ -e "$bundle" ]; then cp -R "$bundle" "$STAGE/Contents/Resources/"; fi
done

if security find-identity -p codesigning | grep -q "\"$SIGN_IDENTITY\""; then
    if ! codesign --force --deep --options runtime --sign "$SIGN_IDENTITY" "$STAGE"; then
        echo "ERROR: signing with \"$SIGN_IDENTITY\" failed. If the error is errSecInternalComponent, run once:" >&2
        echo "       security set-key-partition-list -S apple-tool:,apple: -s ~/Library/Keychains/login.keychain-db" >&2
        echo "       $APP was left unchanged." >&2
        exit 1
    fi
    echo "Signed with \"$SIGN_IDENTITY\""
else
    codesign --force --deep --sign - "$STAGE"
    echo "WARNING: identity \"$SIGN_IDENTITY\" not found; signed ad-hoc."
    echo "         Accessibility permission will reset after every rebuild."
fi
codesign --verify --strict "$STAGE"

rm -rf "$APP"
mv "$STAGE" "$APP"
rm -rf build/.staging

# Keep this development copy out of Launch Services, so opening "Shortkeys"
# (Spotlight, Launchpad, the reopen-to-show-Settings path) uses the installed
# app in /Applications. `open build/Shortkeys.app` still works.
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREGISTER" -u "$APP" 2>/dev/null || true
echo "Built $APP"
