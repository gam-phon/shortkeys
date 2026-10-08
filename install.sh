#!/bin/bash
# Builds Shortkeys and installs it into /Applications.
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

# Quit the running copy first; replacing a running app's binary gets it killed.
pkill -x Shortkeys 2>/dev/null && sleep 1 || true

rm -rf /Applications/Shortkeys.app
cp -R build/Shortkeys.app /Applications/
open /Applications/Shortkeys.app
echo "Installed /Applications/Shortkeys.app"
