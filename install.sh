#!/bin/bash
# Builds Shortkeys and installs it into /Applications.
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

# Quit the running copy first; replacing a running app's binary gets it killed.
if pkill -x Shortkeys 2>/dev/null; then
    # Wait until it has really exited (up to 10 s), then make sure.
    for _ in $(seq 50); do pgrep -x Shortkeys >/dev/null || break; sleep 0.2; done
    pkill -9 -x Shortkeys 2>/dev/null || true
fi

# Move (not copy) so there's only ever one Shortkeys on the Mac.
rm -rf /Applications/Shortkeys.app
mv build/Shortkeys.app /Applications/
open -n /Applications/Shortkeys.app
echo "Installed /Applications/Shortkeys.app"
