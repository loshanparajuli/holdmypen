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

# The editor and storage layers, which are what these tests exercise. The
# SwiftUI views are left out on purpose: @State is a macro now, and expanding
# it needs the SwiftUIMacros plugin that only ships inside Xcode — including
# them here would make the tests unrunnable on plain Command Line Tools.
SOURCES=(
    "$ROOT/holdmyPen/EditorTypography.swift"
    "$ROOT/holdmyPen/WrapGrid.swift"
    "$ROOT/holdmyPen/EditorTextView.swift"
    "$ROOT/holdmyPen/FloatingImageView.swift"
    "$ROOT/holdmyPen/Models/Note.swift"
    "$ROOT/holdmyPen/Models/NoteStore.swift"
)

swiftc -target "$(uname -m)-apple-macosx14.0" \
    -swift-version 5 \
    -o "$WORK_DIR/tests" \
    "${SOURCES[@]}" \
    "$ROOT"/Tests/*.swift

# The bundled fonts are registered by the app at launch; the test binary has no
# bundle, so point it at the sources on disk.
HOLDMYPEN_FONT_DIR="$ROOT/holdmyPen" "$WORK_DIR/tests"
