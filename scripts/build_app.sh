#!/bin/bash
# Builds holdmyPen.app without Xcode, using only Command Line Tools.
#
# Usage: scripts/build_app.sh [output_dir] [signing_identity]
#
# Xcode's toolchain isn't required here, which also means its two asset-catalog
# steps aren't available: the app icon is compiled with iconutil into a plain
# .icns instead, and the About panel's logo is copied in as a loose resource.
# NSImage(named:) finds it either way. Everything else — deployment target,
# whole-module optimization, universal binary, hardened runtime — matches the
# project's Release configuration.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC="$ROOT/holdmyPen"

OUTPUT_DIR="${1:-$ROOT/build}"
# Pass "-" to ad-hoc sign, which is all a build you only intend to run on this
# machine needs; distribution still wants a real Developer ID.
IDENTITY="${2:-Developer ID Application}"

DEPLOYMENT_TARGET=14.0
BUNDLE_ID=com.holdmypen.app
APP="$OUTPUT_DIR/holdmyPen.app"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SRC/Info.plist")"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# --- Executable (universal, matching the Release configuration) -------------

# Built without -DDEBUG, so the #Preview block is left out: its macro needs a
# plugin that ships with Xcode rather than Command Line Tools.
SOURCES=("$SRC"/*.swift "$SRC"/Models/*.swift)

# `@State` is an attached macro in current SDKs, and expanding it needs the
# SwiftUIMacros plugin — an Xcode component that the Command Line Tools have
# never carried. Without it every SwiftUI view here fails to compile, which
# would leave this script unable to do the one thing it exists for. When the
# plugin is missing, build from a copy of the sources with `@State` pointed at
# scripts/CompatState.swift, which forwards to the same property wrapper the
# macro expands to. The checked-in sources stay plain SwiftUI; only this
# build's copy of them is rewritten.
if ! find "$(xcrun --find swiftc | sed 's|/usr/bin/swiftc||')/usr/lib/swift/host/plugins" \
        -name 'libSwiftUIMacros.dylib' 2>/dev/null | grep -q .; then
    echo "note: SwiftUIMacros plugin not found (no Xcode); building @State through scripts/CompatState.swift"
    SHIMMED="$WORK_DIR/sources"
    mkdir -p "$SHIMMED/Models"
    cp "$SRC"/*.swift "$SHIMMED/"
    cp "$SRC"/Models/*.swift "$SHIMMED/Models/"
    cp "$SCRIPT_DIR/CompatState.swift" "$SHIMMED/"
    # Only the attribute; `@StateObject` has no space after it and is untouched.
    sed -i '' 's/@State /@CompatState /g' "$SHIMMED"/*.swift
    SOURCES=("$SHIMMED"/*.swift "$SHIMMED"/Models/*.swift)
fi

for arch in arm64 x86_64; do
    swiftc \
        -target "$arch-apple-macosx$DEPLOYMENT_TARGET" \
        -swift-version 5 \
        -O -wmo \
        -parse-as-library \
        -Xlinker -dead_strip \
        -o "$WORK_DIR/holdmyPen-$arch" \
        "${SOURCES[@]}"
done

lipo -create -output "$APP/Contents/MacOS/holdmyPen" \
    "$WORK_DIR/holdmyPen-arm64" "$WORK_DIR/holdmyPen-x86_64"

# --- Resources --------------------------------------------------------------

cp "$SRC"/PTSerif-*.ttf "$SRC/suffer.mp3" "$APP/Contents/Resources/"

# The About panel looks this up with NSImage(named: "AppLogo").
cp "$SRC/Assets.xcassets/AppLogo.imageset/logo.png" "$APP/Contents/Resources/AppLogo.png"

ICONSET="$WORK_DIR/holdmyPen.iconset"
mkdir -p "$ICONSET"
for size in 16x16 32x32 128x128 256x256 512x512; do
    cp "$SRC/Assets.xcassets/AppIcon.appiconset/icon_$size.png" "$ICONSET/icon_$size.png"
    cp "$SRC/Assets.xcassets/AppIcon.appiconset/icon_$size@2x.png" "$ICONSET/icon_$size@2x.png"
done
iconutil --convert icns --output "$APP/Contents/Resources/holdmyPen.icns" "$ICONSET"

# --- Info.plist -------------------------------------------------------------

# The checked-in plist is written for Xcode, so its $(...) build settings have
# to be substituted here.
sed -e 's|\$(DEVELOPMENT_LANGUAGE)|en|' \
    -e 's|\$(EXECUTABLE_NAME)|holdmyPen|' \
    -e "s|\$(PRODUCT_BUNDLE_IDENTIFIER)|$BUNDLE_ID|" \
    -e 's|\$(PRODUCT_NAME)|holdmyPen|' \
    -e 's|\$(PRODUCT_BUNDLE_PACKAGE_TYPE)|APPL|' \
    -e "s|\$(MACOSX_DEPLOYMENT_TARGET)|$DEPLOYMENT_TARGET|" \
    "$SRC/Info.plist" > "$APP/Contents/Info.plist"

PLIST="$APP/Contents/Info.plist"
# CFBundleIconName points at an asset-catalog icon that isn't in this bundle;
# a loose .icns is named by CFBundleIconFile instead.
/usr/libexec/PlistBuddy -c 'Delete :CFBundleIconName' "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c 'Add :CFBundleIconFile string holdmyPen' "$PLIST"
# Set by Xcode from INFOPLIST_KEY_* build settings rather than the plist file.
/usr/libexec/PlistBuddy -c 'Add :CFBundleDisplayName string holdmyPen' "$PLIST"
/usr/libexec/PlistBuddy -c 'Add :LSApplicationCategoryType string public.app-category.productivity' "$PLIST"
plutil -convert binary1 "$PLIST"

# --- Signing ----------------------------------------------------------------

# --options runtime is the hardened runtime (ENABLE_HARDENED_RUNTIME = YES),
# and notarization refuses anything without it. The timestamp is likewise
# required — but a secure timestamp needs a real identity and the network, so
# an ad-hoc local build asks for neither.
if [ "$IDENTITY" = "-" ]; then
    codesign --force --sign - "$APP"
else
    codesign --force --timestamp --options runtime \
        --sign "$IDENTITY" \
        "$APP"
fi

codesign --verify --strict --verbose=2 "$APP"

echo "Built $APP (version $VERSION)"
codesign -dv "$APP" 2>&1 | grep -E 'Identifier|TeamIdentifier|flags'
