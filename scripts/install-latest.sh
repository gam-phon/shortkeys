#!/bin/bash
# Installs, or updates to, the latest Shortkeys release in /Applications:
#   curl -fsSL https://raw.githubusercontent.com/gam-phon/shortkeys/main/scripts/install-latest.sh | bash
# Downloads with curl aren't quarantined, so macOS doesn't block the app.
# Variables are always written as ${NAME}: in some locales bash would read a
# following non-ASCII character as part of the name. Keep this file ASCII-only.
set -euo pipefail

REPO="gam-phon/shortkeys"
# For testing only: install somewhere else and don't open the app.
APPS_DIR="${SHORTKEYS_APPS_DIR:-/Applications}"
OPEN_APP="${SHORTKEYS_OPEN:-1}"
APP="${APPS_DIR}/Shortkeys.app"

TAG="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | plutil -extract tag_name raw -o - -)"
VERSION="${TAG#v}"
BASE="https://github.com/${REPO}/releases/download/${TAG}"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

echo "Downloading Shortkeys ${VERSION}..."
curl -fsSL -o "${TMP}/Shortkeys-${VERSION}.zip" "${BASE}/Shortkeys-${VERSION}.zip"
curl -fsSL -o "${TMP}/SHA256SUMS.txt" "${BASE}/SHA256SUMS.txt"
(cd "${TMP}" && grep " Shortkeys-${VERSION}.zip$" SHA256SUMS.txt | shasum -a 256 -c - >/dev/null)
ditto -x -k "${TMP}/Shortkeys-${VERSION}.zip" "${TMP}/unpacked"
codesign --verify --strict "${TMP}/unpacked/Shortkeys.app"

FIRST_INSTALL=1
[ -e "${APP}" ] && FIRST_INSTALL=0
if [ "${OPEN_APP}" = 1 ]; then
    pkill -x Shortkeys 2>/dev/null && sleep 1 || true
fi
ditto "${TMP}/unpacked/Shortkeys.app" "${APP}.updating"
# A copy installed by an older .pkg belongs to root; removing it needs sudo.
if [ -e "${APP}" ] && [ ! -O "${APP}" ]; then
    echo "Removing the old copy (installed as administrator) needs your password:"
    sudo rm -rf "${APP}"
else
    rm -rf "${APP}"
fi
mv "${APP}.updating" "${APP}"

if [ "${FIRST_INSTALL}" = 1 ]; then
    # Setup mode: turns on Launch at Login, opens Settings and asks for Accessibility.
    [ "${OPEN_APP}" = 1 ] && open "${APP}" --args --setup
    cat <<MSG
Installed Shortkeys ${VERSION} in ${APPS_DIR}.

One last step: macOS asks you to allow Shortkeys under Accessibility.
Click "Open System Settings" and turn on Shortkeys. Hotkeys start working right away.
MSG
else
    [ "${OPEN_APP}" = 1 ] && open "${APP}"
    echo "Updated Shortkeys to ${VERSION}."
fi
