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
CERT_NAME="${SIGNING_CERT_NAME:-Sleight Development}"

# Prefer a certificate if one exists. Run Scripts/create-signing-cert.sh to make
# one; it is the difference between granting permission once and granting it
# after every build.
# find-identity, not find-certificate: the latter matches substrings anywhere in
# the keychain and does not require the private key, so a cert whose key had gone
# missing still looked usable and skipped the ad-hoc fallback.
if [ -z "${SIGN_ID:-}" ] && security find-identity -p codesigning | grep -qF "$CERT_NAME"; then
    SIGN_ID="$CERT_NAME"
fi
export SIGN_ID="${SIGN_ID:--}"

"$ROOT/Scripts/bundle.sh"

echo "stopping any running copy"
# Anchored on the executable path: -f matches the whole command line, so a loose
# "Sleight.app" also matched editors and shells that merely mention the path.
PATTERN="/Sleight\.app/Contents/MacOS/Sleight$"
pkill -f "$PATTERN" 2>/dev/null || true

# Wait for it to actually go. A fixed sleep let a slow exit survive, after which
# the newly installed copy saw an instance already running, terminated itself,
# and the script reported success while the old build kept going.
for _ in $(seq 1 30); do
    pgrep -f "$PATTERN" >/dev/null 2>&1 || break
    sleep 0.2
done
if pgrep -f "$PATTERN" >/dev/null 2>&1; then
    echo "it did not exit; forcing"
    pkill -9 -f "$PATTERN" 2>/dev/null || true
    sleep 0.5
fi

if [ "$SIGN_ID" = "-" ]; then
    echo "clearing the stale Accessibility entry (ad-hoc signature)"
    if ! tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1; then
        echo "  warning: tccutil failed; you may have to remove the entry by hand" >&2
    fi
else
    echo "signed as '$SIGN_ID'; existing Accessibility permission still applies"
fi

rm -rf "$DEST"
cp -R "$ROOT/build/Sleight.app" "$DEST"
open "$DEST"

if [ "$SIGN_ID" = "-" ]; then
    # The registration is tied to the signature, which an ad-hoc build changes.
    echo "note: if 'Open at Login' was on, switch it off and on again."
fi

echo
echo "installed to $DEST"
if [ "$SIGN_ID" = "-" ]; then
    echo "Grant Accessibility permission when asked; the app picks it up within a second."
fi
echo "log: ~/Library/Logs/Sleight.log"
