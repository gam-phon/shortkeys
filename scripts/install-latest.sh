#!/bin/bash
# Installs, or updates to, the latest Shortkeys release in /Applications:
#   curl -fsSL https://raw.githubusercontent.com/gam-phon/shortkeys/main/scripts/install-latest.sh | bash
# Downloads with curl aren't quarantined, so macOS doesn't block the app.
set -euo pipefail

REPO="gam-phon/shortkeys"
TAG="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" | plutil -extract tag_name raw -o - -)"
VERSION="${TAG#v}"
BASE="https://github.com/$REPO/releases/download/$TAG"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Downloading Shortkeys $VERSION…"
curl -fsSL -o "$TMP/Shortkeys-$VERSION.zip" "$BASE/Shortkeys-$VERSION.zip"
curl -fsSL -o "$TMP/SHA256SUMS.txt" "$BASE/SHA256SUMS.txt"
(cd "$TMP" && grep " Shortkeys-$VERSION.zip$" SHA256SUMS.txt | shasum -a 256 -c - >/dev/null)
ditto -x -k "$TMP/Shortkeys-$VERSION.zip" "$TMP/unpacked"
codesign --verify --strict "$TMP/unpacked/Shortkeys.app"

pkill -x Shortkeys 2>/dev/null && sleep 1 || true
ditto "$TMP/unpacked/Shortkeys.app" /Applications/Shortkeys.app.updating
rm -rf /Applications/Shortkeys.app
mv /Applications/Shortkeys.app.updating /Applications/Shortkeys.app
open /Applications/Shortkeys.app
echo "Installed Shortkeys $VERSION in /Applications."
