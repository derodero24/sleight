#!/bin/bash
# Builds, installs to /Applications, and launches.
#
# The awkward part is Accessibility permission. An ad-hoc signature's designated
# requirement is the cdhash:
#
#     codesign -d -r- Sleight.app
#     # designated => cdhash H"b9ee566b..."
#
# That value changes on every build, so the entry already sitting in Accessibility
# settings stops matching the new binary. It keeps showing Sleight with its switch
# on while the app is told it has no permission, and no amount of toggling helps -
# the entry has to be removed and re-added. This script removes it for you.
#
# Signing with a real identity instead makes the requirement cert-based and stable
# across builds, at which case permission survives updates and the reset below
# becomes unnecessary. Set SIGN_ID to use one.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE_ID="dev.sleight.Sleight"
DEST="/Applications/Sleight.app"

"$ROOT/Scripts/bundle.sh"

echo "stopping any running copy"
pkill -f "Sleight.app" 2>/dev/null || true
sleep 1

if [ "${SIGN_ID:--}" = "-" ]; then
    echo "clearing the stale Accessibility entry (ad-hoc signature)"
    tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
fi

rm -rf "$DEST"
cp -R "$ROOT/build/Sleight.app" "$DEST"
open "$DEST"

echo
echo "installed to $DEST"
if [ "${SIGN_ID:--}" = "-" ]; then
    echo "Grant Accessibility permission when asked; the app picks it up within a second."
fi
echo "log: ~/Library/Logs/Sleight.log"
