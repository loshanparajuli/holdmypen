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

# Everything except the @main entry point, which would fight with the test
# runner's own top-level code.
SOURCES=()
for file in "$ROOT"/holdmyPen/*.swift "$ROOT"/holdmyPen/Models/*.swift; do
    [ "$(basename "$file")" = "holdmyPenApp.swift" ] && continue
    SOURCES+=("$file")
done

# Built without -DDEBUG, which leaves out the #Preview block: its macro needs a
# plugin that ships with Xcode rather than Command Line Tools.
swiftc -target "$(uname -m)-apple-macosx14.0" \
    -o "$WORK_DIR/tests" \
    "${SOURCES[@]}" \
    "$ROOT"/Tests/*.swift

# The bundled fonts are registered by the app at launch; the test binary has no
# bundle, so point it at the sources on disk.
HOLDMYPEN_FONT_DIR="$ROOT/holdmyPen" "$WORK_DIR/tests"
