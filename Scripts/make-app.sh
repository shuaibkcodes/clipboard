#!/bin/bash
# Builds ClipboardMac.app for the current host architecture and optionally a
# .dmg.
#
# Usage:
#   ./Scripts/make-app.sh          # build build/ClipboardMac.app
#   ./Scripts/make-app.sh --dmg    # also create build/ClipboardMac.dmg
set -euo pipefail

cd "$(dirname "$0")/.."

BUILD_ARCH="$(uname -m)"
case "$BUILD_ARCH" in
    arm64|x86_64) ;;
    *)
        echo "Unsupported architecture: $BUILD_ARCH" >&2
        exit 1
        ;;
esac

echo "Building release binary ($BUILD_ARCH)..."
swift build -c release --arch "$BUILD_ARCH"

APP="build/ClipboardMac.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cp ".build/${BUILD_ARCH}-apple-macosx/release/ClipboardMac" "$APP/Contents/MacOS/ClipboardMac"
cp Scripts/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc signature: gives the app a stable identity so Accessibility
# permission survives rebuilds. Replace "-" with your Developer ID
# certificate name for distribution.
codesign --force --sign - "$APP"

echo "Built $APP"

if [[ "${1:-}" == "--dmg" ]]; then
    DMG="build/ClipboardMac.dmg"
    rm -f "$DMG"
    STAGING="$(mktemp -d)"
    cp -R "$APP" "$STAGING/"
    ln -s /Applications "$STAGING/Applications"
    hdiutil create -volname "ClipboardMac" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
    rm -rf "$STAGING"
    echo "Built $DMG"
fi
