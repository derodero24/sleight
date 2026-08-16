#!/bin/bash
# Builds, signs, notarizes and staples a distributable Sleight.app.
#
#     SIGN_ID="Developer ID Application: Name (TEAMID)" ./Scripts/release.sh
#
# Store the notarization credentials once, before the first run:
#
#     xcrun notarytool store-credentials sleight-notary \
#         --apple-id you@example.com --team-id TEAMID --password <app-specific>
#
# The password is an app-specific one from appleid.apple.com, not the Apple
# account password. Override the profile name with NOTARY_PROFILE.
#
# Notarization is an automated malware scan, not review: it usually answers in a
# few minutes. What it checks is the signature, which is why this refuses to
# submit anything it can already tell will be rejected.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/Sleight.app"
ZIP="$ROOT/build/Sleight.zip"
PROFILE="${NOTARY_PROFILE:-sleight-notary}"

if [ -z "${SIGN_ID:-}" ]; then
    echo "SIGN_ID is not set. Releases need a Developer ID Application identity:" >&2
    echo >&2
    security find-identity -p codesigning | grep "Developer ID Application" >&2 \
        || echo "  (none found in the keychain)" >&2
    exit 1
fi

case "$SIGN_ID" in
    "Developer ID Application:"*) ;;
    *)
        # A self-signed identity signs and installs happily but can never be
        # notarized, and finding that out from notarytool's output is slow.
        echo "SIGN_ID is '$SIGN_ID'." >&2
        echo "Only a 'Developer ID Application: ...' identity can be notarized." >&2
        echo "For local installs use Scripts/install.sh instead." >&2
        exit 1
        ;;
esac

SIGN_ID="$SIGN_ID" "$ROOT/Scripts/bundle.sh"

echo
echo "== verifying the signature before submitting =="
# Gatekeeper's own view, which is what the download will be judged by. Doing it
# here means a rejection costs seconds rather than a round trip to Apple.
codesign --verify --strict --deep --verbose=2 "$APP"
if ! codesign -dvv "$APP" 2>&1 | grep -q "Timestamp="; then
    echo "no secure timestamp in the signature; notarization would reject it" >&2
    exit 1
fi
codesign -dvv "$APP" 2>&1 | grep -E "Authority|TeamIdentifier|Timestamp" || true

echo
echo "== submitting =="
rm -f "$ZIP"
# ditto, not zip: it preserves the bundle's symlinks and extended attributes,
# and a plain zip can produce an archive Apple rejects as malformed.
/usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

echo
echo "== stapling =="
# Staples the ticket into the bundle so it validates without a network round
# trip. Without this a first launch offline is refused.
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

# Re-zip after stapling: the archive made above does not contain the ticket.
rm -f "$ZIP"
/usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"

echo
echo "== what a downloader will see =="
spctl --assess --type execute --verbose=4 "$APP"

echo
echo "ready: $ZIP"
