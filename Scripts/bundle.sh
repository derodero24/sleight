#!/bin/bash
# Wraps the built binary into a .app bundle.
#
# This is not cosmetic. macOS keys Accessibility permission off the code
# signature, and macOS 26.1 has an Apple-side bug where a bare executable never
# shows up in the permission list at all. A signed bundle is the only reliable
# way for a user to grant permission.
set -euo pipefail

NAME="${1:-Sleight}"
# Every build wrote version 1, so Launch Services had nothing to notice when a
# bundle was replaced in place. The commit count is monotonic and free.
BUILD="$(git -C "$(dirname "${BASH_SOURCE[0]}")/.." rev-list --count HEAD 2>/dev/null || echo 1)"
BUNDLE_ID="${BUNDLE_ID:-dev.sleight.Sleight}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/$NAME.app"

swift build -c release --package-path "$ROOT"
BINARY="$(swift build -c release --package-path "$ROOT" --show-bin-path)/Sleight"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BINARY" "$APP/Contents/MacOS/$NAME"

# Localizations. Kept as .lproj directories in Contents/Resources rather than as
# SwiftPM resources, so Bundle.main finds them and SwiftUI's Text picks them up
# with no per-call bundle argument. macOS then honours the per-app language set in
# System Settings > General > Language & Region, which is where people already
# look; an in-app language picker would only compete with it.
mkdir -p "$APP/Contents/Resources"
cp -R "$ROOT/Resources/"*.lproj "$APP/Contents/Resources/"

# The icon is not decoration here: the app's central instruction is "find
# Sleight in the Accessibility list", and without one it appears there, and in
# Login Items, as an anonymous grey placeholder.
if [ -f "$ROOT/Icon/Sleight.icns" ]; then
    cp "$ROOT/Icon/Sleight.icns" "$APP/Contents/Resources/"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>$NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>$NAME</string>
    <key>CFBundleIconFile</key><string>Sleight</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key>
    <array><string>en</string><string>ja</string></array>
    <!-- Menu-bar/background app: no Dock icon, no window. -->
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signing is enough to test locally. Shipping needs a Developer ID
# certificate, so that Gatekeeper accepts it on someone else's Mac. The tap
# itself needs Accessibility, which is granted per app rather than by signature.
SIGN_ID="${SIGN_ID:--}"
# No fallback: every shipping codesign supports --options runtime, so a retry
# without it could only hide the real error and quietly drop hardened runtime.
codesign --force --sign "$SIGN_ID" --options runtime --timestamp=none "$APP"

echo "built  $APP"
codesign -dv "$APP" 2>&1 | grep -E 'Identifier|Signature|TeamIdentifier' || true
