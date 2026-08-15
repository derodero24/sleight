#!/bin/bash
# Wraps the built binary into a .app bundle.
#
# This is not cosmetic. macOS keys Accessibility permission off the code
# signature, and macOS 26.1 has an Apple-side bug where a bare executable never
# shows up in the permission list at all. A signed bundle is the only reliable
# way for a user to grant permission.
set -euo pipefail

NAME="${1:-Sleight}"
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

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>$NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>$NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
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
# certificate - Launch Services requires one for CGEventTap + Input Monitoring,
# which makes the $99/year Apple Developer Program a hard dependency.
SIGN_ID="${SIGN_ID:--}"
codesign --force --sign "$SIGN_ID" --options runtime --timestamp=none "$APP" 2>/dev/null \
    || codesign --force --sign "$SIGN_ID" "$APP"

echo "built  $APP"
codesign -dv "$APP" 2>&1 | grep -E 'Identifier|Signature|TeamIdentifier' || true
