#!/bin/bash
# Compiles and runs the window geometry tests.
set -euo pipefail
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cp scripts/test-geometry.swift "$TMP/main.swift"
swiftc "$TMP/main.swift" Sources/Shortkeys/WindowGeometry.swift -o "$TMP/test-geometry"
"$TMP/test-geometry"
