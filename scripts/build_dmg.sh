#!/bin/bash
# Packages a built holdmyPen.app into a distributable DMG with the classic
# "drag into Applications" arrow layout.
#
# Usage: scripts/build_dmg.sh /path/to/holdmyPen.app [output.dmg]
#
# Run this after building the real app in Xcode (Product > Archive > Export,
# or the .app under DerivedData) — it does not build the app itself.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_PATH="${1:?Usage: build_dmg.sh /path/to/holdmyPen.app [output.dmg]}"
OUTPUT_DMG="${2:-$SCRIPT_DIR/../holdmyPen-installer.dmg}"
VOL_NAME="holdmyPen"

if [ ! -d "$APP_PATH" ]; then
    echo "error: app not found at $APP_PATH" >&2
    exit 1
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

STAGING="$WORK_DIR/staging"
mkdir -p "$STAGING/.background"

cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# Render the arrow background image fresh each time, so editing the Swift
# source is enough to change the artwork.
swift "$SCRIPT_DIR/generate_dmg_background.swift" "$STAGING/.background/background.png"

RW_DMG="$WORK_DIR/rw.dmg"
hdiutil create -volname "$VOL_NAME" -srcfolder "$STAGING" -ov -format UDRW "$RW_DMG" >/dev/null

MOUNT_DIR="/Volumes/$VOL_NAME"
# No custom -mountpoint and no -nobrowse: Finder's `disk "..."` reference
# below only recognizes volumes mounted at their default /Volumes path.
hdiutil attach "$RW_DMG" -quiet

APP_NAME="$(basename "$APP_PATH")"

osascript <<OSA
tell application "Finder"
    tell disk "$VOL_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {100, 100, 780, 520}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 128
        set background picture of viewOptions to file ".background:background.png"
        set position of item "$APP_NAME" of container window to {150, 146}
        set position of item "Applications" of container window to {510, 146}
        close
        open
        update without registering applications
        delay 1
    end tell
end tell
OSA

sync
hdiutil detach "$MOUNT_DIR" -quiet

rm -f "$OUTPUT_DMG"
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$OUTPUT_DMG" >/dev/null

echo "Created $OUTPUT_DMG"
