#!/bin/bash
# Runs the editor's headless tests.
#
# The project has no Xcode test target, so the app's own sources are compiled
# together with Tests/ into a single executable and run. Works with plain
# Command Line Tools — no Xcode required.
#
# Usage: scripts/run_tests.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

# `#Preview` needs Xcode's macro plugin, which isn't part of Command Line
# Tools, so the previews are stripped from the copies we compile. They're
# development-only scaffolding and none of the tests touch them.
mkdir -p "$WORK_DIR/src"
for file in "$ROOT"/holdmyPen/*.swift "$ROOT"/holdmyPen/Models/*.swift; do
    name="$(basename "$file")"
    # The @main entry point would fight with the test runner's own top level.
    [ "$name" = "holdmyPenApp.swift" ] && continue
    awk '/^#Preview/ { depth = 1; next }
         depth > 0 { depth += gsub(/{/, "{") - gsub(/}/, "}"); next }
         { print }' "$file" > "$WORK_DIR/src/$name"
done

swiftc -target "$(uname -m)-apple-macosx14.0" \
    -o "$WORK_DIR/tests" \
    "$WORK_DIR/src"/*.swift \
    "$ROOT"/Tests/*.swift

# The bundled fonts are registered by the app at launch; the test binary has no
# bundle, so point it at the sources on disk.
HOLDMYPEN_FONT_DIR="$ROOT/holdmyPen" "$WORK_DIR/tests"
